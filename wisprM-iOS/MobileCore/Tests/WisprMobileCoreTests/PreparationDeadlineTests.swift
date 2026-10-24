import XCTest
@testable import WisprMobileCore

final class PreparationDeadlineTests: XCTestCase {
    func testTimeoutDoesNotWaitForAnUncooperativeNativeCallback() async {
        let finished = expectation(description: "Native callback eventually releases its resources")
        let callback = expectation(description: "Native callback arrived")
        let status = CallbackStatus()
        do {
            let _: Int = try await PreparationDeadline.run(timeout: .milliseconds(20), onFinished: { finished.fulfill() }) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        status.markFired()
                        callback.fulfill()
                        continuation.resume(returning: 7)
                    }
                }
            }
            XCTFail("The native callback must not beat the deadline")
        } catch {
            XCTAssertEqual(error as? PreparationDeadlineError, .timedOut)
        }
        XCTAssertFalse(status.hasFired, "The UI deadline must return before the uncooperative native callback, not wait for it.")
        // Wait for the late callback too: no abandoned test work or double resume.
        await fulfillment(of: [callback, finished], timeout: 2)
    }

    func testAlreadyCancelledTaskDoesNotStartNativeWork() async {
        let finished = expectation(description: "Cancelled worker cleaned up")
        let start = StartGate()
        let task = Task {
            await start.wait()
            return try await PreparationDeadline.run(timeout: .seconds(1), onFinished: { finished.fulfill() }) {
                XCTFail("Already-cancelled preparation must not invoke native loading")
                return 1
            }
        }
        task.cancel()
        await start.open()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [finished], timeout: 2)
    }

    func testSuccessAndFailureCompleteExactlyOnce() async throws {
        for value in 0..<40 {
            let result = try await PreparationDeadline.run(timeout: .seconds(1)) { value }
            XCTAssertEqual(result, value)
        }
        do {
            let _: Int = try await PreparationDeadline.run(timeout: .seconds(1)) { throw TestFailure.expected }
            XCTFail("Expected native failure")
        } catch { XCTAssertTrue(error is TestFailure) }
    }
}

private enum TestFailure: Error { case expected }
private final class CallbackStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    var hasFired: Bool { lock.lock(); defer { lock.unlock() }; return fired }
    func markFired() { lock.lock(); fired = true; lock.unlock() }
}
private actor StartGate {
    private var ready = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        if !ready { await withCheckedContinuation { waiter = $0 } }
    }
    func open() { ready = true; waiter?.resume(); waiter = nil }
}
