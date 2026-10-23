import Darwin
import Foundation
import XCTest
@testable import WisprM
import WisprCore

@MainActor final class RuntimeLifecycleTests: XCTestCase {
    private struct Fixture {
        let directory: URL
        let runtime: LocalRuntime
        var childPIDFile: URL { directory.appendingPathComponent("child.pid") }
    }

    private func fixture(mode: String = "normal", maximumLineBytes: Int = 4096) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wisprm-worker-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("worker.py")
        let source = #"""
        import json,os,signal,subprocess,sys,time
        from pathlib import Path
        mode = sys.argv[1]
        child_file = Path(sys.argv[2])
        if os.getpgrp() != os.getpid():
            os.setsid()
        def stopping(signum, frame):
            raise SystemExit(128+signum)
        signal.signal(signal.SIGTERM, stopping)
        print(json.dumps({"event":"ready","pid":os.getpid(),"process_group":os.getpgrp() if mode != "badready" else os.getpgrp()+1}), flush=True)
        for line in sys.stdin:
            request = json.loads(line)
            if request.get("op") == "quit":
                break
            if mode == "oversize":
                print("x"*8192, flush=True)
                continue
            if request.get("op") == "transcribe" and mode == "child":
                child = subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"],
                                         stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                child_file.write_text(str(child.pid))
                try:
                    child.wait()
                finally:
                    if child.poll() is None:
                        child.terminate()
                    child.wait()
            if request.get("op") == "transcribe" and mode == "ignore":
                signal.signal(signal.SIGTERM,signal.SIG_IGN)
                child_file.write_text(str(os.getpid()))
                time.sleep(30)
            print(json.dumps({"id":request["id"],"ok":True,"text":"fixture transcript","language":"en"}),flush=True)
        """#
        try source.write(to: script, atomically: true, encoding: .utf8)
        var configuration = LocalRuntime.Configuration(executable: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-u", script.path, mode, directory.appendingPathComponent("child.pid").path])
        configuration.environment = ["HOME": directory.path, "TMPDIR": directory.path,
                                     "WISPRM_RECORDINGS_DIR": directory.appendingPathComponent("recordings").path]
        configuration.maximumLineBytes = maximumLineBytes
        configuration.readinessTimeout = 2
        configuration.prepareTimeout = 2
        configuration.transcribeTimeout = 3
        configuration.shutdownGrace = 0.2
        let runtime = LocalRuntime(configuration: configuration)
        addTeardownBlock {
            await runtime.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        return Fixture(directory: directory, runtime: runtime)
    }

    private func waitForPID(_ url: URL) async throws -> pid_t {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let data = try? String(contentsOf: url), let pid = Int32(data) { return pid }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NSError(domain: "wisprM.Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture child did not start"])
    }

    func testCompletedRequestsCancelTheirWatchdogs() async throws {
        let fixture = try fixture()
        try await fixture.runtime.prepare(engine: .whisper, model: "fixture")
        XCTAssertEqual(fixture.runtime.pendingRequestCount, 0)
        XCTAssertEqual(fixture.runtime.activeWatchdogCount, 0)
        let text = try await fixture.runtime.transcribe(url: fixture.directory.appendingPathComponent("unused.wav"), language: "en")
        XCTAssertEqual(text.text, "fixture transcript")
        XCTAssertEqual(fixture.runtime.pendingRequestCount, 0)
        XCTAssertEqual(fixture.runtime.activeWatchdogCount, 0)
    }

    func testCancellationStopsDecoderAndAwaitsOldWorkerBeforeRestart() async throws {
        let fixture = try fixture(mode: "child")
        try await fixture.runtime.prepare(engine: .whisper, model: "fixture")
        let oldPID = try XCTUnwrap(fixture.runtime.workerProcessIdentifier)
        let request = Task { try await fixture.runtime.transcribe(url: fixture.directory.appendingPathComponent("unused.wav"), language: "en") }
        let childPID = try await waitForPID(fixture.childPIDFile)
        fixture.runtime.requestShutdown()
        try await fixture.runtime.prepare(engine: .whisper, model: "replacement")
        do { _ = try await request.value; XCTFail("Cancelled request must fail") } catch {}
        XCTAssertNotEqual(fixture.runtime.workerProcessIdentifier, oldPID)
        XCTAssertEqual(Darwin.kill(oldPID, 0), -1)
        XCTAssertEqual(Darwin.kill(childPID, 0), -1)
        XCTAssertEqual(fixture.runtime.pendingRequestCount, 0)
        XCTAssertEqual(fixture.runtime.activeWatchdogCount, 0)
    }

    func testUncooperativeOwnedWorkerIsKilledAfterGrace() async throws {
        let fixture = try fixture(mode: "ignore")
        try await fixture.runtime.prepare(engine: .whisper, model: "fixture")
        let request = Task { try await fixture.runtime.transcribe(url: fixture.directory.appendingPathComponent("unused.wav"), language: "en") }
        let pid = try await waitForPID(fixture.childPIDFile)
        let start = ProcessInfo.processInfo.systemUptime
        await fixture.runtime.shutdown()
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        XCTAssertEqual(Darwin.kill(pid, 0), -1)
        do { _ = try await request.value; XCTFail("Cancelled request must fail") } catch {}
    }

    func testOversizedProtocolLineFailsWithoutWaitingForRequestTimeout() async throws {
        let fixture = try fixture(mode: "oversize", maximumLineBytes: 128)
        let start = ProcessInfo.processInfo.systemUptime
        do {
            try await fixture.runtime.prepare(engine: .whisper, model: "fixture")
            XCTFail("Oversized worker data must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("message-size")) }
        await fixture.runtime.shutdown()
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        XCTAssertEqual(fixture.runtime.pendingRequestCount, 0)
    }

    func testInvalidProcessGroupHandshakeIsRejected() async throws {
        let fixture = try fixture(mode: "badready")
        do {
            try await fixture.runtime.prepare(engine: .whisper, model: "fixture")
            XCTFail("An unrelated process group must never be trusted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("owned process group")) }
        await fixture.runtime.shutdown()
        XCTAssertNil(fixture.runtime.workerProcessIdentifier)
        XCTAssertEqual(fixture.runtime.activeWatchdogCount, 0)
    }

    func testLineLimitAppliesAcrossChunksAndAfterNewlines() throws {
        let buffer = WorkerLineBuffer(maximumBytes: 5)
        XCTAssertEqual(try buffer.append(Data("ab\n123".utf8)), [Data("ab".utf8)])
        XCTAssertThrowsError(try buffer.append(Data("456".utf8)))
    }
}
