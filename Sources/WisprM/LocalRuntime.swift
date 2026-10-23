import Foundation
import Combine
import WisprCore

private final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ chunk: Data) -> [Data] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [Data] = []
        while let end = data.firstIndex(of: 10) {
            lines.append(data.subdata(in: 0..<end))
            data.removeSubrange(0...end)
        }
        if data.count > 4_000_000 { data.removeAll() }
        return lines
    }
}

struct RecognizedSpeech { let text: String; let language: String }

@MainActor final class LocalRuntime: ObservableObject {
    @Published var busy = false
    @Published var message = "Choose a local speech model"
    @Published var loadedKey: String?
    @Published var installed = FileManager.default.isExecutableFile(atPath: AppPaths.runtime.appendingPathComponent("bin/python3").path)
        && FileManager.default.fileExists(atPath: AppPaths.runtime.appendingPathComponent(".wisprm-ready").path)
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var workerToken = UUID()
    private var installer: Process?

    func install() async throws {
        guard !busy else { return }
        busy = true; message = "Installing local runtime. This can take a few minutes…"
        defer { busy = false }
        let candidates = ["/opt/homebrew/bin/python3.13", "/opt/homebrew/bin/python3.12"] +
            ((try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/.pyenv/versions")) ?? [])
                .filter { $0.hasPrefix("3.12") || $0.hasPrefix("3.11") }.map { NSHomeDirectory() + "/.pyenv/versions/" + $0 + "/bin/python3" } +
            ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        guard let python = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AppFailure("Install Python 3.10 or later for Apple Silicon, then try again.")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [AppPaths.resources.appendingPathComponent("setup-runtime.sh").path, AppPaths.runtime.path, python]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        installer = task
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try task.run() } catch { task.terminationHandler = nil; continuation.resume(throwing: error) }
        }
        installer = nil
        guard status == 0 else { throw AppFailure("Runtime installation failed. Check your connection and Python installation; you can retry safely.") }
        installed = true; message = "Runtime installed. Download a model to begin."
    }

    func prepare(engine: SpeechEngine, model: String) async throws {
        guard !busy else { return }
        busy = true; loadedKey = nil; message = "Downloading or loading \(engine.rawValue)…"
        defer { busy = false }
        _ = try await request(["op": "prepare", "engine": engine.rawValue, "model": model], timeout: 1800)
        loadedKey = engine.rawValue + "|" + model
        message = "\(engine.rawValue) is ready · on this Mac"
    }

    func transcribe(url: URL, language: String) async throws -> RecognizedSpeech {
        let response = try await request(["op": "transcribe", "audio": url.path, "language": language], timeout: 180)
        return RecognizedSpeech(text: response["text"] as? String ?? "", language: response["language"] as? String ?? language)
    }

    private func startWorker() throws {
        guard process?.isRunning != true else { return }
        guard installed else { throw AppFailure("Install the local runtime in Models first.") }
        let token = UUID(); workerToken = token
        let task = Process(), stdin = Pipe(), stdout = Pipe()
        task.executableURL = AppPaths.runtime.appendingPathComponent("bin/python3")
        task.arguments = ["-u", AppPaths.resources.appendingPathComponent("worker.py").path]
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environment["DO_NOT_TRACK"] = "1"
        environment["PATH"] = AppPaths.runtime.appendingPathComponent("bin").path + ":/opt/homebrew/bin:/usr/bin:/bin"
        task.environment = environment
        task.standardInput = stdin; task.standardOutput = stdout; task.standardError = FileHandle.nullDevice
        let buffer = LineBuffer()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            for line in buffer.append(chunk) {
                Task { @MainActor [weak self] in self?.receive(line, token: token) }
            }
        }
        task.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.workerToken == token else { return }
                self.failPending("The local model worker stopped. Load the model again.")
                self.loadedKey = nil
            }
        }
        do { try task.run() } catch { stdout.fileHandleForReading.readabilityHandler = nil; throw error }
        process = task; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
    }

    private func request(_ payload: [String: Any], timeout: UInt64) async throws -> [String: Any] {
        try startWorker()
        let id = UUID().uuidString
        var payload = payload; payload["id"] = id
        var data = try JSONSerialization.data(withJSONObject: payload); data.append(10)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try input?.write(contentsOf: data) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error); return }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeout * 1_000_000_000)
                guard let self, self.pending[id] != nil else { return }
                self.shutdown()
                self.message = "The local model timed out. Try a smaller model."
            }
        }
    }

    private func receive(_ data: Data, token: UUID) {
        guard token == workerToken, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = value["id"] as? String else { return }
        if value["event"] as? String == "progress" {
            message = value["message"] as? String ?? message
            return
        }
        guard let continuation = pending.removeValue(forKey: id) else { return }
        if value["ok"] as? Bool == true { continuation.resume(returning: value) }
        else { continuation.resume(throwing: AppFailure(value["error"] as? String ?? "Local inference failed.")) }
    }

    private func failPending(_ message: String) {
        let continuations = pending.values; pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: AppFailure(message)) }
    }

    func shutdown() {
        workerToken = UUID()
        output?.readabilityHandler = nil
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
        if installer?.isRunning == true { installer?.terminate() }
        process = nil; input = nil; output = nil; loadedKey = nil
        failPending("Local processing was cancelled.")
        message = "Model unloaded"
    }
}
