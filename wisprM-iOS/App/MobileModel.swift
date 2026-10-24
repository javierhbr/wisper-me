import SwiftUI
import UIKit
import WisprCore
import WisprMobileCore
import WisprMobileInference

@MainActor final class MobileModel: ObservableObject {
    enum Phase: String { case idle, preparing, authorizing, recording, transcribing, polishing, cancelling }
    @Published var tab = 0
    @Published var preferences: MobilePreferences { didSet {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "mobile.preferences.v1") }
        if oldValue.historyEnabled && !preferences.historyEnabled { clearHistory() }
        if oldValue.polishMode != preferences.polishMode || oldValue.serverEndpoint != preferences.serverEndpoint {
            polishTask?.cancel()
        }
    } }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var loadedID: String?
    @Published private(set) var textModelID: String?
    @Published private(set) var progress: Double = 0
    @Published var transcript = ""
    @Published var message = "Choose a local model to begin."
    @Published var error: String?
    @Published private(set) var history: [Transcript] = []
    @Published private(set) var receipts: [String: ModelReceipt] = [:]
    let recorder = AudioRecorder()
    private let defaults: UserDefaults
    private let speech = SpeechRuntime()
    private let textRuntime = TextRuntime()
    private let server = Polisher()
    private var work: Task<Void, Never>?
    private var polishTask: Task<String, Error>?
    private var recordingPreferences: MobilePreferences?
    private var needsCopy = false
    private var isIntegrationRun = false
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    var busy: Bool { phase != .idle }
    var ready: Bool { loadedID == preferences.speechChoice.id }

    init() {
        let store = MobilePaths.integration ? UserDefaults(suiteName: (Bundle.main.bundleIdentifier ?? "wisprM") + ".integration")! : .standard
        defaults = store
        preferences = store.data(forKey: "mobile.preferences.v1")
            .flatMap { try? JSONDecoder().decode(MobilePreferences.self, from: $0) } ?? MobilePreferences()
        receipts = store.data(forKey: "mobile.models.v1")
            .flatMap { try? JSONDecoder().decode([String: ModelReceipt].self, from: $0) } ?? [:]
        do {
            try MobilePaths.prepare()
            if preferences.historyEnabled { history = try MobilePaths.archive.load() }
            else { try MobilePaths.archive.clear() }
        } catch { self.error = error.localizedDescription }
        recorder.onFinish = { [weak self] url in
            guard let self else { return }
            self.process(url, snapshot: self.recordingPreferences ?? self.preferences)
        }
        recorder.onError = { [weak self] error in self?.phase = .idle; self?.error = error.localizedDescription }
    }

    func loadSpeech() {
        guard !busy else { return }
        let choice = preferences.speechChoice
        if choice.repository == "local", receipts[choice.id]?.folder.map({ FileManager.default.fileExists(atPath: $0.path) }) != true {
            error = "This imported model is missing. Import its folder again from Files."; return
        }
        phase = .preparing; progress = 0; error = nil; loadedID = nil
        message = "Downloading or loading \(choice.name)…"
        work = Task {
            defer { self.phase = .idle; self.work = nil }
            do {
                await textRuntime.unload(); textModelID = nil
                let folder = try await speech.prepare(choice, directory: MobilePaths.models,
                    existing: receipts[choice.id]?.folder, progress: { [weak self] value in
                        Task { @MainActor in if self?.phase == .preparing { self?.progress = value } }
                    })
                try Task.checkCancellation()
                let bytes: Int64
                do { bytes = try await Task.detached(priority: .utility) { try ModelReceipt.measure(folder) }.value }
                catch { throw MobileFailure.message("Model storage inspection failed: \(error.localizedDescription)") }
                let prefix = MobilePaths.models.path + "/"
                guard folder.path.hasPrefix(prefix) else { throw MobileFailure.message("The model was downloaded outside its storage directory.") }
                receipts[choice.id] = ModelReceipt(relativePath: String(folder.path.dropFirst(prefix.count)), bytes: bytes)
                saveReceipts(); loadedID = choice.id; message = "\(choice.name) is ready. Audio stays on this iPhone."
            } catch {
                await speech.unload()
                #if DEBUG
                if isIntegrationRun { FileHandle.standardError.write(Data("wisprM prepare failure: \(String(reflecting: error)) · \((error as NSError).userInfo)\n".utf8)) }
                #endif
                if error is CancellationError { message = "Model loading cancelled." }
                else { self.error = error.localizedDescription }
            }
        }
    }

    func loadTextModel() {
        guard !busy else { return }
        let id = preferences.localTextModel.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .preparing; progress = 0; message = "Downloading or loading the text model…"; error = nil
        work = Task {
            defer { phase = .idle; work = nil }
            do {
                await speech.unload(); loadedID = nil
                try await textRuntime.prepare(id: id, localDirectory: localTextDirectory(preferences), cacheDirectory: MobilePaths.models.appendingPathComponent("Text")) { [weak self] value in
                    Task { @MainActor in if self?.phase == .preparing { self?.progress = value } }
                }
                textModelID = id; message = "Text model downloaded. Load your speech model next. Text weights remain cached."
            } catch {
                textModelID = nil
                if error is CancellationError { message = "Text model loading cancelled." }
                else { self.error = error.localizedDescription }
            }
        }
    }

    func start() {
        guard !busy else { return }
        guard ready else { tab = 1; error = "Download and load the selected speech model first."; return }
        let snapshot = preferences; recordingPreferences = snapshot
        phase = .authorizing; error = nil
        work = Task {
            defer { work = nil }
            do {
                try await recorder.start(in: MobilePaths.recordings)
                try Task.checkCancellation()
                phase = .recording; message = "Listening. Tap Finish when you are done."
            } catch {
                recorder.cancel(); phase = .idle
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func finish() { if phase == .recording { recorder.finish() } }

    private func process(_ url: URL, snapshot: MobilePreferences) {
        phase = .transcribing; message = "Transcribing on your iPhone…"
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish dictation") { [weak self] in
            self?.endBackgroundWork()
            self?.cancel()
        }
        work = Task {
            defer {
                try? FileManager.default.removeItem(at: url)
                endBackgroundWork()
                phase = .idle; work = nil; polishTask = nil
            }
            do {
                let conversion = Task.detached(priority: .userInitiated) { try AudioDecoder.samples(from: url) }
                let samples: [Float]
                do { samples = try await withTaskCancellationHandler { try await conversion.value } onCancel: { conversion.cancel() } }
                catch is CancellationError { throw CancellationError() }
                catch { throw MobileFailure.message("Audio conversion failed: \(error.localizedDescription)") }
                var text: String
                do { text = try await speech.transcribe(samples, choice: snapshot.speechChoice, language: snapshot.language) }
                catch is CancellationError { throw CancellationError() }
                catch { throw MobileFailure.message("Speech recognition failed: \(error.localizedDescription)") }
                try Task.checkCancellation()
                guard !text.isEmpty else { throw MobileFailure.message("No speech was recognized. Try a clearer or longer recording.") }
                text = TextFormatter().format(text, style: snapshot.style,
                    locale: snapshot.language == "auto" ? "und" : snapshot.language, interpretCommands: snapshot.spokenCommands)
                if snapshot.polishMode == .local && UIApplication.shared.applicationState != .active && mayPolish(snapshot) {
                    self.error = "On-device polishing requires wisprM to remain open. Local cleanup was kept."
                }
                if mayPolish(snapshot) && (snapshot.polishMode != .local || UIApplication.shared.applicationState == .active) {
                    phase = .polishing; message = "Polishing your words…"
                    let original = text
                    let polishing = Task<String, Error> {
                        if snapshot.polishMode == .local {
                            await speech.unload(); loadedID = nil
                            try await textRuntime.prepare(id: snapshot.localTextModel, localDirectory: localTextDirectory(snapshot), cacheDirectory: MobilePaths.models.appendingPathComponent("Text")) { _ in }
                            try Task.checkCancellation()
                            return try await textRuntime.polish(original, modelID: snapshot.localTextModel, style: snapshot.style.rawValue)
                        }
                        return try await server.polish(original, style: snapshot.style, configuration: .init(
                            endpoint: snapshot.serverEndpoint, model: snapshot.serverModel,
                            apiKey: MobileCredentialStore.read(endpoint: snapshot.serverEndpoint)))
                    }
                    polishTask = polishing
                    let polishResult = await polishing.result
                    if snapshot.polishMode == .local { await textRuntime.unload(); textModelID = nil }
                    do { let result = try polishResult.get(); if mayPolish(snapshot) { text = result } }
                    catch {
                        try Task.checkCancellation()
                        if mayPolish(snapshot) { self.error = "Polishing was unavailable; local cleanup was kept. " + error.localizedDescription }
                    }
                }
                try Task.checkCancellation()
                let result = Transcript(text: text, model: snapshot.speechChoice.name)
                transcript = text; needsCopy = true
                if snapshot.historyEnabled && preferences.historyEnabled {
                    history.insert(result, at: 0); history = Array(history.prefix(30))
                    do { try MobilePaths.archive.save(history) } catch { self.error = error.localizedDescription }
                }
                do { try MobilePaths.exchange?.publish(result) } catch { self.error = "Text is ready, but keyboard sharing failed. " + error.localizedDescription }
                message = "Text is ready. Open the wisprM keyboard to insert it, or paste from the clipboard."
                copyWhenActive()
            } catch {
                if error is CancellationError { message = "Cancelled. No text was inserted." }
                else { self.error = error.localizedDescription }
            }
        }
    }

    private func mayPolish(_ captured: MobilePreferences) -> Bool {
        MobilePolishingConsent.allows(captured: captured, live: preferences)
    }
    private func endBackgroundWork() {
        let token = backgroundTask; backgroundTask = .invalid
        if token != .invalid { UIApplication.shared.endBackgroundTask(token) }
    }
    private func localTextDirectory(_ preferences: MobilePreferences) -> URL? {
        guard let path = preferences.localTextFolder else { return nil }
        return ModelReceipt(relativePath: path, bytes: 0).folder
    }
    func copy() {
        guard !transcript.isEmpty else { return }
        UIPasteboard.general.string = transcript; needsCopy = false; message = "Copied. Paste your text into another app."
    }
    func copyWhenActive() {
        if let exchange = MobilePaths.exchange, (try? exchange.latest()) == nil { try? exchange.clear() }
        if needsCopy && !isIntegrationRun && UIApplication.shared.applicationState == .active { copy() }
    }
    func suspendLocalPolishing() {
        if phase == .polishing && preferences.polishMode == .local { polishTask?.cancel() }
    }
    func cancel() {
        if phase == .recording { recorder.cancel(); phase = .idle; message = "Recording cancelled."; return }
        guard busy else { return }
        phase = .cancelling; message = "Cancelling. Waiting for the current model operation to finish…"
        polishTask?.cancel(); work?.cancel()
    }
    func importAudio(_ source: URL) {
        guard !busy, ready else { error = "Load a speech model before importing audio."; return }
        phase = .preparing; message = "Importing audio…"
        let snapshot = preferences
        work = Task {
            let destination = MobilePaths.recordings.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let copy = Task.detached(priority: .utility) {
                let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 100 * 1024 * 1024 else { throw MobileFailure.message("Imports are limited to 100 MB.") }
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: source, to: destination)
                try Task.checkCancellation()
            }
            do {
                try await withTaskCancellationHandler { try await copy.value } onCancel: { copy.cancel() }
                try Task.checkCancellation()
                process(destination, snapshot: snapshot)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                phase = .idle; work = nil
                if error is CancellationError { message = "Import cancelled." } else { self.error = error.localizedDescription }
            }
        }
    }
    func unload() {
        guard !busy else { return }
        phase = .preparing
        work = Task { await speech.unload(); await textRuntime.unload(); loadedID = nil; textModelID = nil; phase = .idle; work = nil; message = "Models unloaded. Downloaded files remain on this iPhone." }
    }
    func addWhisperRepository(_ repository: String, variant: String) {
        guard !busy else { return }
        let repository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        let variant = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard repository.count <= 256, variant.count <= 128,
              repository.range(of: #"^[\w.-]+/[\w.-]+$"#, options: .regularExpression) != nil,
              variant.range(of: #"^[\w.-]+$"#, options: .regularExpression) != nil else {
            error = "Enter an owner/repository ID and the compatible WhisperKit variant folder name."; return
        }
        let choice = SpeechChoice(id: "custom-" + UUID().uuidString, name: variant, engine: .whisper, repository: repository, variant: variant)
        preferences.customSpeechChoice = choice; preferences.modelID = choice.id
    }
    func importModelFolder(_ source: URL, forText: Bool) {
        guard !busy else { return }
        let engine = preferences.speechChoice.engine
        phase = .preparing; message = "Importing model files…"; error = nil
        work = Task {
            defer { phase = .idle; work = nil }
            await speech.unload(); await textRuntime.unload(); loadedID = nil; textModelID = nil
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let relative = "Imported/" + UUID().uuidString
            let folder = MobilePaths.models.appendingPathComponent(relative)
            let copy = Task.detached(priority: .utility) {
                try ModelFolderImport.copy(from: source, to: folder)
                return try ModelReceipt.measure(folder)
            }
            do {
                let bytes = try await withTaskCancellationHandler { try await copy.value } onCancel: { copy.cancel() }
                try Task.checkCancellation()
                if forText {
                    preferences.localTextFolder = relative
                    preferences.localTextModel = "Imported " + source.lastPathComponent
                    preferences.polishMode = .local
                } else {
                    let choice = SpeechChoice(id: "imported-" + UUID().uuidString, name: source.lastPathComponent,
                        engine: engine, repository: "local", variant: source.lastPathComponent)
                    preferences.customSpeechChoice = choice; preferences.modelID = choice.id
                    receipts[choice.id] = ModelReceipt(relativePath: relative, bytes: bytes); saveReceipts()
                }
                message = "Model files imported. Tap Load to validate and use them."
            } catch {
                try? FileManager.default.removeItem(at: folder)
                if error is CancellationError { message = "Model import cancelled." } else { self.error = error.localizedDescription }
            }
        }
    }
    func deleteModel(_ choice: SpeechChoice) {
        guard !busy, let folder = receipts[choice.id]?.folder else { return }
        phase = .preparing
        work = Task {
            defer { phase = .idle; work = nil }
            await speech.unload(); loadedID = nil
            do {
                if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
                receipts.removeValue(forKey: choice.id); saveReceipts(); message = "Downloaded model deleted."
            } catch { self.error = error.localizedDescription }
        }
    }
    func deleteAllModels() {
        guard !busy else { return }
        phase = .preparing
        work = Task {
            defer { phase = .idle; work = nil }
            await speech.unload(); await textRuntime.unload(); loadedID = nil; textModelID = nil
            do {
                if FileManager.default.fileExists(atPath: MobilePaths.models.path) { try FileManager.default.removeItem(at: MobilePaths.models) }
                receipts = [:]; preferences.localTextFolder = nil; preferences.customSpeechChoice = nil
                preferences.modelID = SpeechChoice.presets[0].id
                preferences.localTextModel = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
                saveReceipts(); message = "Managed model files, including partial downloads, were removed."
            } catch { self.error = error.localizedDescription }
        }
    }
    func clearHistory() {
        do { try MobilePaths.archive.clear(); history = [] } catch { self.error = error.localizedDescription }
    }
    func clearSharedText() {
        do { try MobilePaths.exchange?.clear(); message = "Shared keyboard transcript cleared." } catch { self.error = error.localizedDescription }
    }
    private func saveReceipts() { if let data = try? JSONEncoder().encode(receipts) { defaults.set(data, forKey: "mobile.models.v1") } }

    #if DEBUG
    /// Developer integration path uses the same loader, decoder, formatter and result delivery.
    /// Test input must be a generated fixture in this app's Documents directory.
    func runIntegrationIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--integration-audio"), index + 1 < args.count else { return }
        let documents = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        let input = args[index + 1]
        let file = (input.hasPrefix("/") ? URL(fileURLWithPath: input) : documents.appendingPathComponent(input)).standardizedFileURL
        guard file.path.hasPrefix(NSHomeDirectory() + "/Documents/"), !busy else { return }
        isIntegrationRun = true
        let idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled }
        preferences.polishMode = .off; preferences.historyEnabled = false
        if let polishing = args.firstIndex(of: "--integration-polish-model"), polishing + 1 < args.count {
            preferences.localTextModel = args[polishing + 1]; preferences.localTextFolder = nil; preferences.polishMode = .local
        }
        defer { preferences.polishMode = .off }
        if let engine = args.firstIndex(of: "--integration-model"), engine + 1 < args.count { preferences.modelID = args[engine + 1] }
        let started = Date()
        loadSpeech()
        if let current = work { await current.value }
        if ready {
            process(file, snapshot: preferences)
            if let current = work { await current.value }
        }
        let result: [String: Any] = ["model": preferences.modelID, "text": transcript,
            "error": error ?? "", "seconds": Date().timeIntervalSince(started), "sharedContainer": MobilePaths.group != nil,
            "loadedModel": loadedID ?? ""]
        let output = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/integration-result.json")
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output, options: .atomic) }
    }
    #endif
}
