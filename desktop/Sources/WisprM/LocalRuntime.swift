import Foundation
import Combine
import Darwin
import WisprCore

enum WorkerProtocolError: LocalizedError {
    case lineTooLong, invalidHandshake
    var errorDescription: String? {
        switch self {
        case .lineTooLong: return "The local worker exceeded its message-size limit."
        case .invalidHandshake: return "The local worker did not establish an owned process group."
        }
    }
}

final class WorkerLineBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    let maximumBytes: Int
    init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

    func append(_ chunk: Data) throws -> [Data] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [Data] = []
        while let end = data.firstIndex(of: 10) {
            guard end <= maximumBytes else { data.removeAll(); throw WorkerProtocolError.lineTooLong }
            lines.append(data.subdata(in: 0..<end))
            data.removeSubrange(0...end)
        }
        guard data.count <= maximumBytes else { data.removeAll(); throw WorkerProtocolError.lineTooLong }
        return lines
    }
}

/// Foundation owns reaping the directly launched Process; this latch waits without blocking the main actor.
private final class ProcessExitMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuations: [CheckedContinuation<Int32, Never>] = []
    var hasExited: Bool { lock.lock(); defer { lock.unlock() }; return status != nil }
    func finish(_ value: Int32) {
        lock.lock()
        guard status == nil else { lock.unlock(); return }
        status = value
        let waiting = continuations; continuations.removeAll()
        lock.unlock()
        for continuation in waiting { continuation.resume(returning: value) }
    }
    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status { lock.unlock(); continuation.resume(returning: status) }
            else { continuations.append(continuation); lock.unlock() }
        }
    }
}

private final class WorkerInput: @unchecked Sendable {
    let handle: FileHandle
    private let queue = DispatchQueue(label: "com.wisprm.worker-input")
    init(_ handle: FileHandle) {
        self.handle = handle
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
    }
    func send(_ data: Data, completion: @escaping @Sendable (Error?) -> Void) {
        queue.async {
            do { try self.handle.write(contentsOf: data); completion(nil) }
            catch { completion(error) }
        }
    }
    func close() async {
        await withCheckedContinuation { continuation in
            queue.async { try? self.handle.close(); continuation.resume() }
        }
    }
}

struct RecognizedSpeech { let text: String; let language: String }

@MainActor final class LocalRuntime: ObservableObject {
    struct Configuration {
        let executable: URL
        let arguments: [String]
        var installed: Bool = true
        var environment: [String: String]?
        var maximumLineBytes = 1_048_576
        var readinessTimeout: TimeInterval = 10
        var prepareTimeout: TimeInterval = 1800
        var transcribeTimeout: TimeInterval = 180
        var shutdownGrace: TimeInterval = 2
    }

    private final class Worker {
        let token = UUID()
        let process: Process
        let input: WorkerInput
        let output: FileHandle
        let exit = ProcessExitMonitor()
        var group: pid_t?
        var ready = false
        var readiness: [CheckedContinuation<Void, Error>] = []
        var readinessWatchdog: Task<Void, Never>?
        init(process: Process, input: WorkerInput, output: FileHandle) {
            self.process = process; self.input = input; self.output = output
        }
    }
    private struct Pending {
        let continuation: CheckedContinuation<[String: Any], Error>
        let watchdog: Task<Void, Never>
    }

    @Published var busy = false
    @Published var message = "Choose a local speech model"
    @Published var loadedKey: String?
    @Published var installed: Bool
    private let configuration: Configuration
    private var worker: Worker?
    private var pending: [String: Pending] = [:]
    private var stopTask: Task<Void, Never>?
    private var activity: UUID?
    private var installer: Process?
    private var installerExit: ProcessExitMonitor?

    // Read-only diagnostics also allow fixture tests to assert that completion releases watchdogs.
    var pendingRequestCount: Int { pending.count }
    var activeWatchdogCount: Int { pending.count + ((worker?.readinessWatchdog == nil) ? 0 : 1) }
    var workerProcessIdentifier: pid_t? { worker?.process.processIdentifier }

    init(configuration: Configuration? = nil) {
        if let configuration {
            self.configuration = configuration
            installed = configuration.installed
        } else {
            let executable = AppPaths.runtime.appendingPathComponent("bin/python3")
            let installed = FileManager.default.isExecutableFile(atPath: executable.path)
                && FileManager.default.fileExists(atPath: AppPaths.runtime.appendingPathComponent(".wisprm-ready").path)
            self.configuration = Configuration(executable: executable,
                arguments: ["-B", "-u", AppPaths.resources.appendingPathComponent("worker.py").path], installed: installed)
            self.installed = installed
        }
    }

    func install() async throws {
        await awaitPriorStop()
        try Task.checkCancellation()
        let activity = try beginActivity()
        message = "Installing local runtime. This can take a few minutes…"
        defer { endActivity(activity) }
        let candidates = ["/opt/homebrew/bin/python3.13", "/opt/homebrew/bin/python3.12"] +
            ((try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/.pyenv/versions")) ?? [])
                .filter { $0.hasPrefix("3.12.") || $0.hasPrefix("3.13.") }
                .map { NSHomeDirectory() + "/.pyenv/versions/" + $0 + "/bin/python3" } +
            ["/usr/local/bin/python3.13", "/usr/local/bin/python3.12"]
        guard let python = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AppFailure("Install Python 3.12 or 3.13 for Apple Silicon, then try again.")
        }
        let process = Process(), exit = ProcessExitMonitor()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [AppPaths.resources.appendingPathComponent("setup-runtime.sh").path, AppPaths.runtime.path, python]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { exit.finish($0.terminationStatus) }
        installer = process; installerExit = exit
        do { try process.run() }
        catch { installer = nil; installerExit = nil; throw error }
        let status = await withTaskCancellationHandler {
            await exit.wait()
        } onCancel: {
            Task { @MainActor [weak self] in self?.requestShutdown() }
        }
        if installer === process { installer = nil; installerExit = nil }
        try Task.checkCancellation()
        guard status == 0 else { throw AppFailure("Runtime installation failed. Check your connection and Python installation; you can retry safely.") }
        installed = true; message = "Runtime installed. Download a model to begin."
    }

    func prepare(engine: SpeechEngine, model: String) async throws {
        await awaitPriorStop()
        try Task.checkCancellation()
        let activity = try beginActivity()
        loadedKey = nil; message = "Downloading or loading \(engine.rawValue)…"
        defer { endActivity(activity) }
        _ = try await request(["op": "prepare", "engine": engine.rawValue, "model": model], timeout: configuration.prepareTimeout)
        try Task.checkCancellation()
        loadedKey = engine.rawValue + "|" + model
        message = "\(engine.rawValue) is ready · on this Mac"
    }

    func transcribe(url: URL, language: String) async throws -> RecognizedSpeech {
        await awaitPriorStop()
        try Task.checkCancellation()
        let activity = try beginActivity()
        defer { endActivity(activity) }
        let response = try await request(["op": "transcribe", "audio": url.path, "language": language], timeout: configuration.transcribeTimeout)
        guard let text = response["text"] as? String else { throw AppFailure("The local worker returned an invalid transcript.") }
        return RecognizedSpeech(text: text, language: response["language"] as? String ?? language)
    }

    private func beginActivity() throws -> UUID {
        guard activity == nil else { throw AppFailure("A local-model operation is already running.") }
        let token = UUID(); activity = token; busy = true
        return token
    }

    private func endActivity(_ token: UUID) {
        guard activity == token else { return }
        activity = nil; busy = false
    }

    private func awaitPriorStop() async {
        while let task = stopTask { await task.value }
    }

    private func ensureWorker() async throws -> Worker {
        await awaitPriorStop()
        if let worker {
            if worker.ready { return worker }
            try await waitUntilReady(worker)
            return worker
        }
        guard installed else { throw AppFailure("Install the local runtime in Models first.") }
        let process = Process(), stdin = Pipe(), stdout = Pipe()
        process.executableURL = configuration.executable
        process.arguments = configuration.arguments
        var environment = configuration.environment ?? ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"; environment["DO_NOT_TRACK"] = "1"
        environment["WISPRM_RECORDINGS_DIR"] = configuration.environment?["WISPRM_RECORDINGS_DIR"] ?? AppPaths.recordings.path
        environment["PATH"] = configuration.executable.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/bin:/bin"
        process.environment = environment
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = FileHandle.nullDevice
        let worker = Worker(process: process, input: WorkerInput(stdin.fileHandleForWriting), output: stdout.fileHandleForReading)
        self.worker = worker
        let buffer = WorkerLineBuffer(maximumBytes: configuration.maximumLineBytes)
        worker.output.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            do {
                let lines = try buffer.append(data)
                Task { @MainActor [weak self] in
                    for line in lines { self?.receive(line, token: worker.token) }
                }
            } catch {
                Task { @MainActor [weak self] in self?.protocolFailure(error, token: worker.token) }
            }
        }
        process.terminationHandler = { [weak self] process in
            worker.exit.finish(process.terminationStatus)
            Task { @MainActor [weak self] in
                guard self?.worker?.token == worker.token else { return }
                self?.requestShutdown(reason: "The local model worker stopped. Load the model again.")
            }
        }
        do { try process.run() }
        catch {
            self.worker = nil; worker.output.readabilityHandler = nil
            process.terminationHandler = nil
            try? worker.output.close()
            await worker.input.close()
            throw error
        }
        let readinessTimeout = configuration.readinessTimeout
        worker.readinessWatchdog = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: Self.nanoseconds(readinessTimeout)) }
            catch { return }
            guard self?.worker?.token == worker.token, !worker.ready else { return }
            self?.requestShutdown(reason: "The local worker did not become ready in time.")
        }
        try await waitUntilReady(worker)
        return worker
    }

    private func waitUntilReady(_ worker: Worker) async throws {
        if worker.ready { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard self.worker?.token == worker.token else {
                continuation.resume(throwing: CancellationError()); return
            }
            worker.readiness.append(continuation)
        }
    }

    private func request(_ payload: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        let id = UUID().uuidString
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let worker = try await ensureWorker()
            try Task.checkCancellation()
            var payload = payload; payload["id"] = id
            var data = try JSONSerialization.data(withJSONObject: payload)
            guard data.count <= configuration.maximumLineBytes else { throw WorkerProtocolError.lineTooLong }
            data.append(10)
            return try await withCheckedThrowingContinuation { continuation in
                let watchdog = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: Self.nanoseconds(timeout)) } catch { return }
                    guard self?.pending[id] != nil else { return }
                    self?.requestShutdown(reason: "The local model timed out. Try a smaller model.")
                }
                pending[id] = Pending(continuation: continuation, watchdog: watchdog)
                worker.input.send(data) { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor in
                        guard self?.worker?.token == worker.token else { return }
                        self?.requestShutdown(reason: error.localizedDescription)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.requestShutdown() }
        }
    }

    private func receive(_ data: Data, token: UUID) {
        guard let worker, worker.token == token else { return }
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            protocolFailure(AppFailure("The local worker returned malformed JSON."), token: token); return
        }
        if value["event"] as? String == "ready" {
            let ownPID = worker.process.processIdentifier
            guard !worker.ready,
                  let pid = value["pid"] as? Int, let group = value["process_group"] as? Int,
                  pid == Int(ownPID), group == Int(ownPID), getpgid(ownPID) == ownPID else {
                protocolFailure(WorkerProtocolError.invalidHandshake, token: token); return
            }
            worker.group = ownPID; worker.ready = true
            worker.readinessWatchdog?.cancel(); worker.readinessWatchdog = nil
            let waiting = worker.readiness; worker.readiness.removeAll()
            for continuation in waiting { continuation.resume() }
            return
        }
        guard worker.ready, let id = value["id"] as? String else {
            protocolFailure(AppFailure("The local worker returned an out-of-order message."), token: token); return
        }
        if value["event"] as? String == "progress" {
            if pending[id] != nil { message = value["message"] as? String ?? message }
            return
        }
        guard let request = pending.removeValue(forKey: id) else { return }
        request.watchdog.cancel()
        if value["ok"] as? Bool == true { request.continuation.resume(returning: value) }
        else { request.continuation.resume(throwing: AppFailure(value["error"] as? String ?? "Local inference failed.")) }
    }

    private func protocolFailure(_ error: Error, token: UUID) {
        guard worker?.token == token else { return }
        requestShutdown(reason: error.localizedDescription)
    }

    func requestShutdown() { requestShutdown(reason: "Local processing was cancelled.") }

    private func requestShutdown(reason: String) {
        loadedKey = nil; message = reason
        activity = nil; busy = false
        guard stopTask == nil else { return }
        let retiringWorker = worker
        let retiringInstaller = installer
        let retiringInstallerExit = installerExit
        worker = nil
        retiringWorker?.readinessWatchdog?.cancel(); retiringWorker?.readinessWatchdog = nil
        let readiness = retiringWorker?.readiness ?? []; retiringWorker?.readiness.removeAll()
        for continuation in readiness { continuation.resume(throwing: AppFailure(reason)) }
        let requests = Array(pending.values); pending.removeAll()
        for request in requests {
            request.watchdog.cancel()
            request.continuation.resume(throwing: AppFailure(reason))
        }
        guard retiringWorker != nil || retiringInstaller != nil else { return }
        retiringWorker?.output.readabilityHandler = nil
        if let retiringWorker {
            retiringWorker.input.send(Data("{\"op\":\"quit\"}\n".utf8)) { _ in }
            Self.signal(retiringWorker, signal: SIGTERM)
        }
        if let retiringInstaller, retiringInstaller.isRunning { retiringInstaller.terminate() }
        stopTask = Task { [weak self] in
            if let retiringWorker {
                await Self.stopAndWait(retiringWorker, grace: self?.configuration.shutdownGrace ?? 2)
                await retiringWorker.input.close()
                try? retiringWorker.output.close()
                retiringWorker.process.terminationHandler = nil
            }
            if let retiringInstaller, let retiringInstallerExit {
                // The installer has its own descendant cleanup grace; let it reap its children first.
                let deadline = ProcessInfo.processInfo.systemUptime + 12
                while !retiringInstallerExit.hasExited && ProcessInfo.processInfo.systemUptime < deadline {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                if !retiringInstallerExit.hasExited { _ = Darwin.kill(retiringInstaller.processIdentifier, SIGKILL) }
                _ = await retiringInstallerExit.wait()
                retiringInstaller.terminationHandler = nil
            }
            self?.installer = nil; self?.installerExit = nil
            self?.stopTask = nil
        }
    }

    func shutdown() async {
        requestShutdown()
        await awaitPriorStop()
    }

    private static func signal(_ worker: Worker, signal: Int32) {
        if let group = worker.group, group == worker.process.processIdentifier {
            _ = Darwin.kill(-group, signal)
        } else if worker.process.isRunning {
            _ = Darwin.kill(worker.process.processIdentifier, signal)
        }
    }

    private static func stopAndWait(_ worker: Worker, grace: TimeInterval) async {
        let deadline = ProcessInfo.processInfo.systemUptime + grace
        while ProcessInfo.processInfo.systemUptime < deadline {
            let groupAlive = worker.group.map { Darwin.kill(-$0, 0) == 0 } ?? false
            if worker.exit.hasExited && !groupAlive { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        // The group was established and checked while the directly owned child was alive.
        signal(worker, signal: SIGKILL)
        _ = await worker.exit.wait()
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0.001, seconds) * 1_000_000_000)
    }
}
