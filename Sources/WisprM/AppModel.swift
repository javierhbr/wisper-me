import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers
import WisprCore

enum Phase: String { case idle, authorizing, recording, transcribing, polishing }
enum Page: String, CaseIterable { case dictate = "Dictate", models = "Models", history = "History", settings = "Settings" }

@MainActor final class AppModel: ObservableObject {
    let settings = SettingsStore()
    let runtime = LocalRuntime()
    let inserter = TextInserter()
    private let recorder = AudioCapture()
    @Published var page: Page = .dictate
    @Published var phase: Phase = .idle
    @Published var transcript = ""
    @Published var rawTranscript = ""
    @Published var note = "Your voice, with room to think."
    @Published var error: String?
    @Published var meter: Float = 0
    @Published var seconds = 0
    @Published var history: [HistoryEntry] = []
    @Published var hotkeyAvailable = true
    @Published var ollamaModels: [String] = []
    @Published var accessibility = AXIsProcessTrusted()
    var showHUD: (() -> Void)?
    var hideHUD: (() -> Void)?
    private var target: TextInserter.Target?
    private var session = UUID()
    private var operation: Task<Void, Never>?
    private var timer: Timer?
    private var sessionPreferences = Preferences()
    private var subscriptions = Set<AnyCancellable>()

    var active: Bool { phase != .idle }
    var recording: Bool { phase == .recording }
    var expectedKey: String { settings.values.engine.rawValue + "|" + settings.values.modelID }
    var modelReady: Bool { runtime.loadedKey == expectedKey }
    var phaseTitle: String {
        switch phase {
        case .idle: return modelReady ? "Ready when you are" : "Make yourself heard"
        case .authorizing: return "Waiting for microphone permission"
        case .recording: return "Listening to you"
        case .transcribing: return "Finding your words"
        case .polishing: return "A little finishing touch"
        }
    }
    init() {
        AppPaths.create()
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        runtime.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        if settings.values.keepHistory,
           let data = try? Data(contentsOf: AppPaths.support.appendingPathComponent("history.json")),
           let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) { history = entries }
    }

    func resumeModelIfPreviouslyLoaded() {
        if UserDefaults.standard.string(forKey: "lastLoadedModel") == expectedKey { loadModel() }
    }
    func importAudio() {
        guard !active, !runtime.busy else { return }
        guard modelReady else { page = .models; error = "Load a local speech model first."; return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        panel.message = "Transcribe an audio file using your selected local model."
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self, response == .OK, let url = panel.url else { return }
                guard !self.active, !self.runtime.busy, self.modelReady else {
                    self.error = "Finish the current operation and load a model before importing audio."; return
                }
                self.transcript = ""; self.rawTranscript = ""
                self.error = nil; self.target = nil; self.session = UUID()
                self.sessionPreferences = self.settings.values
                self.sessionPreferences.autoInsert = false
                self.processAudio(url, deleteAfter: false)
            }
        }
    }
    func loadModel() {
        guard !active, !runtime.busy else { return }
        error = nil
        let preferences = settings.values
        operation = Task {
            do {
                try await runtime.prepare(engine: preferences.engine, model: preferences.modelID)
                UserDefaults.standard.set(expectedKey, forKey: "lastLoadedModel")
                note = "Local model loaded. Press Control–Option–Space in any text field."
            } catch { self.error = error.localizedDescription }
        }
    }
    func installRuntime() {
        guard !active, !runtime.busy else { return }
        error = nil
        operation = Task {
            do { try await runtime.install() } catch { self.error = error.localizedDescription }
        }
    }
    func toggleDictation() {
        if recording { finish(); return }
        guard !active, !runtime.busy else { return }
        guard modelReady else { page = .models; error = "Download and load a speech model first."; return }
        target = inserter.target()
        sessionPreferences = settings.values
        error = nil; session = UUID(); let token = session
        phase = .authorizing
        operation = Task {
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .audio)
            default: authorized = false
            }
            guard self.session == token else { return }
            guard authorized else {
                self.phase = .idle; self.error = "Microphone access is needed. Enable wisprM in System Settings → Privacy & Security → Microphone."; return
            }
            do {
                try recorder.start { [weak self] level in Task { @MainActor in if self?.session == token { self?.meter = level } } }
                transcript = ""; rawTranscript = ""; seconds = 0; phase = .recording
                note = target.map { "Destination: \($0.name). Press the shortcut again to finish." } ?? "Recording to your scratchpad. Press the shortcut again to finish."
                showHUD?()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.phase == .recording else { return }
                        self.seconds += 1
                        if self.seconds >= 180 { self.finish() }
                    }
                }
            } catch { phase = .idle; self.error = error.localizedDescription }
        }
    }

    func finish() {
        guard recording else { return }
        timer?.invalidate(); timer = nil; meter = 0
        let audio: URL
        do { audio = try recorder.stop() }
        catch { phase = .idle; self.error = error.localizedDescription; hideHUD?(); return }
        processAudio(audio, deleteAfter: true)
    }

    private func processAudio(_ audio: URL, deleteAfter: Bool) {
        phase = .transcribing
        let token = session, preferences = sessionPreferences
        operation = Task {
            defer { if deleteAfter { try? FileManager.default.removeItem(at: audio) } }
            do {
                let recognition = try await runtime.transcribe(url: audio, language: preferences.language)
                guard session == token else { return }
                let raw = recognition.text
                rawTranscript = raw
                var text = TextFormatter().format(raw, style: preferences.style, locale: recognition.language)
                guard !text.isEmpty else { throw AppFailure("No words were recognized. Try speaking a little closer to the microphone.") }
                transcript = text
                if preferences.polish {
                    phase = .polishing
                    do {
                        text = try await Polisher().polish(raw, style: preferences.style, configuration: .init(
                            endpoint: preferences.endpoint, model: preferences.textModel, apiKey: CredentialStore.read()))
                    } catch {
                        guard session == token else { return }
                        self.error = "AI polishing was unavailable. Local cleanup was kept. " + error.localizedDescription
                    }
                }
                guard session == token else { return }
                transcript = text; phase = .idle
                if preferences.keepHistory { saveToHistory(text, engine: preferences.engine.rawValue) }
                if preferences.autoInsert, let target { note = inserter.insert(text, into: target) }
                else { note = "Your text is ready. Copy it below, or dictate from another application's text field." }
                hideHUD?()
            } catch {
                guard session == token else { return }
                phase = .idle; self.error = error.localizedDescription; hideHUD?()
            }
        }
    }

    func cancel() {
        session = UUID()
        operation?.cancel(); timer?.invalidate(); timer = nil; recorder.cancel()
        if phase == .transcribing || runtime.busy { runtime.shutdown() }
        phase = .idle; meter = 0; note = "Cancelled. Nothing was inserted."; hideHUD?()
    }
    func copy(_ text: String? = nil) {
        let text = text ?? transcript
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        note = "Copied to clipboard"
    }
    func refreshPermissions() { accessibility = inserter.permitted }
    func clearHistory() {
        history = []
        try? FileManager.default.removeItem(at: AppPaths.support.appendingPathComponent("history.json"))
    }
    private func saveToHistory(_ text: String, engine: String) {
        history.insert(HistoryEntry(id: UUID(), date: Date(), text: text, engine: engine), at: 0)
        history = Array(history.prefix(30))
        guard let data = try? JSONEncoder().encode(history) else { return }
        let path = AppPaths.support.appendingPathComponent("history.json")
        try? data.write(to: path, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
    func discoverTextModels() {
        error = nil
        operation = Task {
            guard let endpoint = EndpointPolicy.validate(settings.values.endpoint),
                  var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { error = PolishError.invalidEndpoint.localizedDescription; return }
            parts.path = "/v1/models"
            guard let url = parts.url else { return }
            var request = URLRequest(url: url); request.timeoutInterval = 5
            let key = CredentialStore.read()
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["data"] as? [[String: Any]] else { throw AppFailure("The server did not return a model list.") }
                ollamaModels = models.compactMap { $0["id"] as? String }.filter { !$0.hasSuffix(":cloud") }.sorted()
                if settings.values.textModel.isEmpty, let first = ollamaModels.first { settings.values.textModel = first }
                note = ollamaModels.isEmpty ? "No local text models found. Install a model in your server, then retry." : "Found \(ollamaModels.count) compatible text models"
            } catch { self.error = "Could not reach the model server. Start Ollama or your compatible server, then retry." }
        }
    }
    func shutdown() { cancel(); runtime.shutdown() }
}
