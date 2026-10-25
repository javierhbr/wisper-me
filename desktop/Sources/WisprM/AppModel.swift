import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers
import WisprCore

enum Phase: String { case idle, authorizing, recording, transcribing, polishing }
enum Page: String, CaseIterable { case dictate = "Dictate", models = "Models", history = "History", settings = "Settings" }

@MainActor final class AudioLevels: ObservableObject {
    @Published var level: Float = 0
}

@MainActor final class AppModel: ObservableObject {
    let settings: SettingsStore
    let runtime: LocalRuntime
    let inserter = TextInserter()
    let audioLevels = AudioLevels()
    private let recorder = AudioCapture()
    private let files: LocalDataStore
    private var polisher: Polisher
    private let clipboardWriter: (String) -> Bool
    private let credentialProvider: (String) -> String
    @Published var page: Page = .dictate
    @Published var phase: Phase = .idle
    @Published var transcript = ""
    @Published var rawTranscript = ""
    @Published var transcriptGeneration = UUID()
    @Published var note = "Your voice, with room to think."
    @Published var error: String?
    @Published var seconds = 0
    @Published var history: [HistoryEntry] = []
    @Published var hotkeyAvailable = true
    @Published var ollamaModels: [String] = []
    @Published var isDiscovering = false
    @Published var accessibility = AXIsProcessTrusted()
    @Published private(set) var isShuttingDown = false
    @Published private(set) var isCleaningUp = false
    var showHUD: (() -> Void)?
    var hideHUD: (() -> Void)?
    private var target: TextInserter.Target?
    private var session = UUID()
    private var discoveryID = UUID()
    private var captureStartTask: Task<Void, Never>?
    private var dictationTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var polishingTask: Task<String, Error>?
    private var cleanupTask: Task<Void, Never>?
    private var timer: Timer?
    private var sessionPreferences = Preferences()
    private var previousPreferences: Preferences
    private var dataReady = false
    private var subscriptions = Set<AnyCancellable>()

    var active: Bool { phase != .idle || isCleaningUp || isShuttingDown }
    var recording: Bool { phase == .recording }
    var hasSavedHistory: Bool { files.mayHaveHistory }
    var expectedKey: String { settings.values.engine.rawValue + "|" + settings.values.modelID }
    var modelReady: Bool { runtime.loadedKey == expectedKey && !runtime.busy && !isShuttingDown }
    var phaseTitle: String {
        switch phase {
        case .idle: return isCleaningUp ? "Finishing cleanup" : modelReady ? "Ready when you are" : "Make yourself heard"
        case .authorizing: return "Waiting for microphone permission"
        case .recording: return "Listening to you"
        case .transcribing: return "Finding your words"
        case .polishing: return "A little finishing touch"
        }
    }

    init(settings: SettingsStore? = nil, files: LocalDataStore? = nil, runtime: LocalRuntime? = nil,
         polisher: Polisher? = nil, clipboardWriter: ((String) -> Bool)? = nil,
         credentialProvider: ((String) -> String)? = nil) {
        self.settings = settings ?? SettingsStore()
        self.files = files ?? LocalDataStore()
        self.runtime = runtime ?? LocalRuntime()
        self.polisher = polisher ?? Polisher()
        self.credentialProvider = credentialProvider ?? { CredentialStore.read(for: $0) }
        self.clipboardWriter = clipboardWriter ?? {
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString($0, forType: .string)
        }
        previousPreferences = self.settings.values
        do {
            try self.files.prepare()
            dataReady = true
            if self.settings.values.keepHistory {
                history = try self.files.loadHistory()
            } else {
                do { try self.files.deleteHistory() }
                catch {
                    history = (try? self.files.loadHistory()) ?? []
                    self.error = "History saving is off, but saved history could not be deleted. Use Delete history to retry."
                }
            }
        } catch { self.error = "Local storage could not be prepared: " + error.localizedDescription }
        self.settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        self.settings.$values.dropFirst().sink { [weak self] values in self?.preferencesChanged(values) }.store(in: &subscriptions)
        self.runtime.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    private func preferencesChanged(_ values: Preferences) {
        let old = previousPreferences
        previousPreferences = values
        if !values.polish || values.endpoint != old.endpoint {
            polishingTask?.cancel()
        }
        if values.endpoint != old.endpoint {
            cancelDiscovery()
            ollamaModels = []
        }
        if old.keepHistory && !values.keepHistory { clearHistory() }
    }
    private func mayPolish(_ captured: Preferences) -> Bool {
        PolishingConsent.allows(capturedEnabled: captured.polish, liveEnabled: settings.values.polish,
                               capturedEndpoint: captured.endpoint, liveEndpoint: settings.values.endpoint)
    }

    func resumeModelIfPreviouslyLoaded() {
        if UserDefaults.standard.string(forKey: "lastLoadedModel") == expectedKey { loadModel() }
    }
    func importAudio() {
        guard !active, !runtime.busy else { return }
        guard modelReady else { page = .models; error = "Load a local speech model first."; return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AudioImportPolicy.extensions.compactMap { UTType(filenameExtension: $0) }; panel.allowsMultipleSelection = false
        panel.message = "Transcribe up to 10 minutes of audio (maximum input size: 100 MiB) with your local model."
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self, response == .OK, let url = panel.url else { return }
                do { try self.transcribeFile(url) }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    func transcribeFile(_ url: URL, temporary: Bool = false) throws {
        guard !active, !runtime.busy, modelReady else {
            throw AppFailure("Finish the current operation and load a model before importing audio.")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard AudioImportPolicy.accepts(fileExtension: url.pathExtension,
                                        bytes: (attributes[.size] as? NSNumber)?.int64Value ?? 0) else {
            throw AppFailure("Choose a supported audio file of at most 100 MiB.")
        }
        cancelDiscovery()
        transcript = ""; rawTranscript = ""; transcriptGeneration = UUID()
        error = nil; target = nil; session = UUID()
        sessionPreferences = settings.values
        sessionPreferences.autoInsert = false
        processAudio(url, deleteAfter: temporary)
    }
    func loadModel() {
        guard !active, !runtime.busy else { return }
        error = nil
        let preferences = settings.values
        setupTask = Task {
            do {
                try Task.checkCancellation()
                try await runtime.prepare(engine: preferences.engine, model: preferences.modelID)
                try Task.checkCancellation()
                UserDefaults.standard.set(preferences.engine.rawValue + "|" + preferences.modelID, forKey: "lastLoadedModel")
                note = "Local model loaded. Press Control–Option–Space in any text field."
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
    func unloadModel() {
        guard !active else { return }
        setupTask?.cancel()
        runtime.requestShutdown()
        setupTask = Task { await runtime.shutdown() }
    }
    func installRuntime() {
        guard !active, !runtime.busy else { return }
        error = nil
        setupTask = Task {
            do { try Task.checkCancellation(); try await runtime.install() }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    func toggleDictation() {
        if recording { finish(); return }
        guard !active, !runtime.busy, dataReady else { return }
        guard modelReady else { page = .models; error = "Download and load a speech model first."; return }
        cancelDiscovery()
        target = inserter.target()
        sessionPreferences = settings.values
        error = nil; session = UUID(); let token = session
        phase = .authorizing
        captureStartTask = Task {
            guard session == token, !Task.isCancelled else { return }
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .audio)
            default: authorized = false
            }
            guard self.session == token, !Task.isCancelled else { return }
            guard authorized else {
                phase = .idle
                error = "Microphone access is needed. Enable wisprM in System Settings → Privacy & Security → Microphone."
                return
            }
            do {
                try recorder.start()
                if let url = recorder.recordingURL { files.trackAudio(url) }
                transcript = ""; rawTranscript = ""; transcriptGeneration = UUID()
                seconds = 0; phase = .recording
                note = target.map { "Destination: \($0.name). Press the shortcut again to finish." }
                    ?? "Recording to your scratchpad. Press the shortcut again to finish."
                showHUD?()
                let ticker = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.phase == .recording else { return }
                        self.audioLevels.level = self.recorder.meter
                        let elapsed = Int(self.recorder.elapsedTime)
                        if self.seconds != elapsed { self.seconds = elapsed }
                        if self.recorder.shouldFinish { self.finish() }
                    }
                }
                timer = ticker
                RunLoop.main.add(ticker, forMode: .common)
            } catch {
                if let url = recorder.recordingURL { files.trackAudio(url) }
                phase = .idle; self.error = error.localizedDescription
            }
        }
    }
    func finish() {
        guard recording else { return }
        timer?.invalidate(); timer = nil; audioLevels.level = 0
        let audio: URL
        do { audio = try recorder.stop() }
        catch {
            phase = .idle; self.error = error.localizedDescription; hideHUD?()
            do { try files.cleanupAudio() } catch { self.error = "Temporary audio could not be deleted. " + error.localizedDescription }
            return
        }
        processAudio(audio, deleteAfter: true)
    }

    private func processAudio(_ audio: URL, deleteAfter: Bool) {
        phase = .transcribing
        let token = session, preferences = sessionPreferences
        if deleteAfter { files.trackAudio(audio) }
        dictationTask = Task {
            defer {
                if deleteAfter {
                    do { try files.releaseAudio(audio) }
                    catch { self.error = "Temporary audio could not be deleted. " + error.localizedDescription }
                }
            }
            do {
                try Task.checkCancellation()
                let recognition = try await runtime.transcribe(url: audio, language: preferences.language)
                guard session == token, !Task.isCancelled else { return }
                let raw = recognition.text
                rawTranscript = raw
                let local = TextFormatter().format(raw, style: preferences.style, locale: recognition.language,
                                                   interpretCommands: preferences.spokenCommands)
                guard !local.isEmpty else { throw AppFailure("No words were recognized. Try speaking closer to the microphone.") }
                var text = local
                transcript = local
                if mayPolish(preferences) {
                    phase = .polishing
                    let configuration = PolishConfiguration(endpoint: preferences.endpoint, model: preferences.textModel,
                                                            apiKey: credentialProvider(preferences.endpoint))
                    let task = Task {
                        try Task.checkCancellation()
                        guard mayPolish(preferences) else { throw CancellationError() }
                        return try await polisher.polish(raw, style: preferences.style, configuration: configuration)
                    }
                    polishingTask = task
                    do {
                        let polished = try await task.value
                        if mayPolish(preferences) { text = polished }
                    } catch {
                        guard session == token, !Task.isCancelled else { return }
                        if mayPolish(preferences), !(error is CancellationError) {
                            self.error = "AI polishing was unavailable. Local cleanup was kept. " + error.localizedDescription
                        }
                    }
                    polishingTask = nil
                }
                guard session == token, !Task.isCancelled else { return }
                transcript = text; phase = .idle
                if preferences.keepHistory && settings.values.keepHistory { saveToHistory(text, engine: preferences.engine.rawValue) }
                let copied = copy(text)
                if preferences.autoInsert && settings.values.autoInsert, let target {
                    let insertion = inserter.insert(text, into: target)
                    note = insertion + (copied ? " · Copied to clipboard. Paste with Command–V." : " · Clipboard copy failed; use Copy to retry.")
                }
                hideHUD?()
            } catch {
                guard session == token, !Task.isCancelled else { return }
                phase = .idle; self.error = error.localizedDescription; hideHUD?()
            }
        }
    }

    func cancel() {
        guard !isCleaningUp else { return }
        let stopWorker = phase == .transcribing || runtime.busy
        let pendingDictation = dictationTask, pendingSetup = setupTask
        session = UUID()
        captureStartTask?.cancel(); dictationTask?.cancel(); polishingTask?.cancel(); setupTask?.cancel()
        cancelDiscovery()
        timer?.invalidate(); timer = nil
        if let url = recorder.recordingURL { files.trackAudio(url) }
        recorder.cancel()
        if stopWorker { runtime.requestShutdown() }
        phase = .idle; audioLevels.level = 0
        note = "Cancelled. Nothing was inserted."; hideHUD?()
        isCleaningUp = true
        cleanupTask = Task {
            if stopWorker { await runtime.shutdown() }
            await pendingDictation?.value
            if stopWorker { await pendingSetup?.value }
            do { try files.cleanupAudio() }
            catch { self.error = "Temporary audio could not be deleted. " + error.localizedDescription }
            isCleaningUp = false
        }
    }
    @discardableResult
    func copy(_ text: String? = nil) -> Bool {
        let text = text ?? transcript
        guard !text.isEmpty else { return false }
        let copied = clipboardWriter(text)
        note = copied ? "Copied to clipboard. Paste anywhere with Command–V." : "Text is ready, but clipboard copy failed. Use Copy to retry."
        return copied
    }
    func refreshPermissions() { accessibility = inserter.permitted }
    func clearHistory() {
        do { try files.deleteHistory(); history = [] }
        catch { self.error = "Saved history could not be deleted. Nothing was reported as deleted. " + error.localizedDescription }
    }
    private func saveToHistory(_ text: String, engine: String) {
        let entries = Array(([HistoryEntry(id: UUID(), date: Date(), text: text, engine: engine)] + history).prefix(30))
        do { try files.saveHistory(entries); history = entries }
        catch { self.error = "Your transcript is ready, but history could not be saved. " + error.localizedDescription }
    }
    func cancelDiscovery() {
        discoveryID = UUID()
        discoveryTask?.cancel(); discoveryTask = nil; isDiscovering = false
    }
    func discoverTextModels() {
        guard !active, !runtime.busy else { return }
        cancelDiscovery()
        error = nil; isDiscovering = true
        let endpoint = settings.values.endpoint, id = UUID()
        discoveryID = id
        let configuration = PolishConfiguration(endpoint: endpoint, model: "", apiKey: credentialProvider(endpoint))
        discoveryTask = Task {
            defer { if discoveryID == id { isDiscovering = false } }
            do {
                let names = try await polisher.listModels(configuration: configuration)
                guard discoveryID == id, settings.values.endpoint == endpoint, !Task.isCancelled else { return }
                ollamaModels = names.filter { !$0.hasSuffix(":cloud") }.sorted()
                if settings.values.textModel.isEmpty, let first = ollamaModels.first { settings.values.textModel = first }
                note = ollamaModels.isEmpty ? "No local text models found. Install one in your server, then retry." : "Found \(ollamaModels.count) compatible text models"
            } catch {
                if discoveryID == id, !Task.isCancelled { self.error = "Could not list models. " + error.localizedDescription }
            }
        }
    }

    /// Called from the deferred application-termination reply; never exits before owned work is reaped.
    func shutdown() async -> Bool {
        isShuttingDown = true
        cancel()
        polisher.shutdown()
        await runtime.shutdown()
        await cleanupTask?.value
        await dictationTask?.value
        await setupTask?.value
        do { try files.cleanupAudio() }
        catch {
            self.error = "Could not delete temporary audio before quitting. " + error.localizedDescription
            isShuttingDown = false; polisher = Polisher()
            return false
        }
        return true
    }
}
