import Foundation

public enum PreparationDeadlineError: Error, Equatable {
    case timedOut
}

/// Stops awaiting a native load even when the framework ignores cancellation.
/// The owner must keep its native-job reservation until onFinished is called.
public enum PreparationDeadline {
    public static func run<Value: Sendable>(timeout: Duration,
        onFinished: @escaping @Sendable () -> Void = {},
        operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let resolution = PreparationResolution<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                resolution.install(continuation)
                let worker = Task.detached(priority: .userInitiated) {
                    defer { onFinished() }
                    guard !resolution.isResolved else { return }
                    do {
                        try Task.checkCancellation()
                        resolution.finish(.success(try await operation()))
                    } catch { resolution.finish(.failure(error)) }
                }
                let timer = Task {
                    do {
                        try await Task.sleep(for: timeout)
                        resolution.finish(.failure(PreparationDeadlineError.timedOut))
                    } catch { /* A completed/cancelled job no longer needs a timer. */ }
                }
                resolution.register([worker, timer])
            }
        } onCancel: { resolution.finish(.failure(CancellationError())) }
    }
}

/// All access to the continuation/result/tasks is protected by the lock. Resume
/// and cancellation occur outside it, including cancellation before installation.
private final class PreparationResolution<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    var isResolved: Bool {
        lock.lock(); defer { lock.unlock() }
        return result != nil
    }
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        let completed = result
        if completed == nil { self.continuation = continuation }
        lock.unlock()
        if let completed { continuation.resume(with: completed) }
    }
    func register(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        let completed = result != nil
        if !completed { self.tasks = tasks }
        lock.unlock()
        if completed { tasks.forEach { $0.cancel() } }
    }
    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
