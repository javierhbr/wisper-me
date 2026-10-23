import Foundation

public enum EndpointOrigin {
    /// Credentials are scoped to an origin, never to whichever endpoint is selected next.
    public static func key(for endpoint: String) -> String? {
        guard let url = EndpointPolicy.validate(endpoint),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(),
              var host = parts.host?.lowercased() else { return nil }
        let port = parts.port ?? (scheme == "https" ? 443 : 80)
        guard (1...65535).contains(port) else { return nil }
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.contains(":") { host = "[\(host)]" }
        return "\(scheme)://\(host):\(port)"
    }
}

/// One bounded transfer; cancellation may arrive before the continuation or task exists.
private final class HTTPTransfer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var buffer = Data()
    private var receivedResponse = false
    private var continuation: CheckedContinuation<Data, Error>?
    private var task: URLSessionDataTask?
    private var result: Result<Data, Error>?

    init(limit: Int) { self.limit = limit }

    var active: Bool {
        lock.lock(); defer { lock.unlock() }
        return result == nil
    }

    func install(_ continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func attach(_ task: URLSessionDataTask) {
        lock.lock()
        let completed = result != nil
        if !completed { self.task = task }
        lock.unlock()
        if completed { task.cancel() }
    }

    func receive(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else {
            complete(.failure(PolishError.invalidResponse), cancel: true); return false
        }
        guard (200..<300).contains(http.statusCode) else {
            complete(.failure(PolishError.service(http.statusCode)), cancel: true); return false
        }
        guard response.expectedContentLength <= Int64(limit) else {
            complete(.failure(PolishError.responseTooLarge), cancel: true); return false
        }
        lock.lock()
        let accepted = result == nil
        if accepted { receivedResponse = true }
        lock.unlock()
        return accepted
    }

    func append(_ chunk: Data) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        guard chunk.count <= limit - buffer.count else {
            lock.unlock()
            complete(.failure(PolishError.responseTooLarge), cancel: true)
            return
        }
        buffer.append(chunk)
        lock.unlock()
    }

    func finish(_ error: Error?) {
        if let error {
            let failure: Error = (error as? URLError)?.code == .cancelled ? CancellationError() : PolishError.requestFailed
            complete(.failure(failure), cancel: false)
            return
        }
        lock.lock()
        let value = buffer
        let valid = receivedResponse
        lock.unlock()
        complete(valid ? .success(value) : .failure(PolishError.invalidResponse), cancel: false)
    }

    func cancel() { complete(.failure(CancellationError()), cancel: true) }
    func close() { complete(.failure(PolishError.clientClosed), cancel: true) }

    private func complete(_ result: Result<Data, Error>, cancel: Bool) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        let task = self.task
        self.continuation = nil
        self.task = nil
        buffer.removeAll()
        lock.unlock()
        if cancel { task?.cancel() }
        continuation?.resume(with: result)
    }
}

/// URLSession retains its delegate. This delegate deliberately never retains its owner.
private final class HTTPDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var transfers: [Int: HTTPTransfer] = [:]

    func register(_ transfer: HTTPTransfer, task: URLSessionDataTask) {
        lock.lock(); transfers[task.taskIdentifier] = transfer; lock.unlock()
    }

    private func transfer(for task: URLSessionTask) -> HTTPTransfer? {
        lock.lock(); defer { lock.unlock() }
        return transfers[task.taskIdentifier]
    }

    func close() {
        lock.lock()
        let pending = Array(transfers.values)
        transfers.removeAll()
        lock.unlock()
        for transfer in pending { transfer.close() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(transfer(for: dataTask)?.receive(response) == true ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        transfer(for: dataTask)?.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let transfer = transfers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        transfer?.finish(error)
    }
}

final class HTTPClient: @unchecked Sendable {
    private let delegate = HTTPDelegate()
    private let session: URLSession
    private let lock = NSLock()
    private var closed = false
    private let maximumBytes: Int

    static func configuration(protocolClasses: [AnyClass]?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.protocolClasses = protocolClasses
        return configuration
    }

    init(protocolClasses: [AnyClass]? = nil, maximumBytes: Int = 256 * 1024) {
        self.maximumBytes = max(1, min(maximumBytes, 1024 * 1024))
        let queue = OperationQueue()
        queue.name = "wisprM.bounded-http"
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: Self.configuration(protocolClasses: protocolClasses),
                             delegate: delegate, delegateQueue: queue)
    }

    func data(for request: URLRequest) async throws -> Data {
        let transfer = HTTPTransfer(limit: maximumBytes)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                transfer.install(continuation)
                start(request, transfer: transfer)
            }
        } onCancel: {
            transfer.cancel()
        }
    }

    private func start(_ request: URLRequest, transfer: HTTPTransfer) {
        lock.lock()
        guard !closed else { lock.unlock(); transfer.close(); return }
        guard transfer.active else { lock.unlock(); return }
        let task = session.dataTask(with: request)
        delegate.register(transfer, task: task)
        transfer.attach(task)
        task.resume()
        lock.unlock()
    }

    func shutdown() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        lock.unlock()
        delegate.close()
        session.invalidateAndCancel()
    }

    deinit { shutdown() }
}
