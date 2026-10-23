import Foundation
import XCTest
@testable import WisprM
import WisprCore

private final class PendingServer: URLProtocol {
    private static let lock = NSLock()
    private static var requests = 0
    private static var cancellations = 0
    static func reset() { lock.lock(); requests = 0; cancellations = 0; lock.unlock() }
    static var counts: (Int, Int) { lock.lock(); defer { lock.unlock() }; return (requests, cancellations) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.lock(); Self.requests += 1; Self.lock.unlock() }
    override func stopLoading() { Self.lock.lock(); Self.cancellations += 1; Self.lock.unlock() }
}

@MainActor final class AppWorkflowTests: XCTestCase {
    private final class ClipboardSink { var values: [String] = [] }
    private struct Fixture {
        let model: AppModel
        let runtime: LocalRuntime
        let files: LocalDataStore
        let settings: SettingsStore
        let audio: URL
        let clipboard: ClipboardSink
    }
    private func fixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wisprm-workflow-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let worker = directory.appendingPathComponent("worker.py")
        try #"""
import json,os,signal,sys,time
if os.getpgrp()!=os.getpid(): os.setsid()
def stop(signum, frame): raise SystemExit(128+signum)
signal.signal(signal.SIGTERM,stop)
print(json.dumps({"event":"ready","pid":os.getpid(),"process_group":os.getpgrp()}),flush=True)
for line in sys.stdin:
    req=json.loads(line)
    if req.get("op")=="quit": break
    if req.get("op")=="transcribe": time.sleep(0.15)
    print(json.dumps({"id":req["id"],"ok":True,"text":"hello team","language":"en"}),flush=True)
"""#.write(to: worker, atomically: true, encoding: .utf8)
        var configuration = LocalRuntime.Configuration(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                                                        arguments: ["-u", worker.path])
        configuration.readinessTimeout = 3
        configuration.prepareTimeout = 3
        configuration.transcribeTimeout = 3
        configuration.shutdownGrace = 0.2
        configuration.environment = ["HOME": directory.path, "TMPDIR": directory.path,
                                     "WISPRM_RECORDINGS_DIR": directory.appendingPathComponent("Recordings").path]
        let runtime = LocalRuntime(configuration: configuration)
        let suite = "wisprm-workflow-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        settings.values.whisperModel = "fixture"
        settings.values.polish = true
        settings.values.endpoint = "https://fixture.invalid/v1/chat/completions"
        settings.values.textModel = "fixture"
        let files = LocalDataStore(root: directory)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PendingServer.self]
        let session = URLSession(configuration: config)
        let polisher = Polisher(session: session)
        session.invalidateAndCancel()
        let clipboard = ClipboardSink()
        PendingServer.reset()
        let model = AppModel(settings: settings, files: files, runtime: runtime, polisher: polisher,
                             clipboardWriter: { clipboard.values.append($0); return true },
                             credentialProvider: { _ in "" })
        addTeardownBlock {
            _ = await model.shutdown()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try await runtime.prepare(engine: .whisper, model: "fixture")
        let audio = files.recordings.appendingPathComponent("fixture.caf")
        try Data("fixture-only; no audio or model inference".utf8).write(to: audio)
        return Fixture(model: model, runtime: runtime, files: files, settings: settings, audio: audio, clipboard: clipboard)
    }
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    func testPrivacyOffDuringTranscriptionNeverSendsToServerAndStillCopiesLocalText() async throws {
        let fixture = try await fixture()
        try fixture.model.transcribeFile(fixture.audio)
        XCTAssertEqual(fixture.model.phase, .transcribing)
        fixture.settings.values.polish = false
        let finished = await eventually { !fixture.model.active }
        XCTAssertTrue(finished)
        XCTAssertEqual(PendingServer.counts.0, 0)
        XCTAssertEqual(fixture.model.transcript, "Hello team.")
        XCTAssertEqual(fixture.clipboard.values, ["Hello team."])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.audio.path), "Imported originals must remain untouched")
    }
    func testDiscoveryCannotStealCancellationFromPendingPolishing() async throws {
        let fixture = try await fixture()
        try fixture.model.transcribeFile(fixture.audio, temporary: true)
        let started = await eventually { fixture.model.phase == .polishing && PendingServer.counts.0 == 1 }
        XCTAssertTrue(started)
        fixture.model.discoverTextModels()
        XCTAssertFalse(fixture.model.isDiscovering)
        fixture.model.cancel()
        let finished = await eventually { !fixture.model.active && PendingServer.counts.1 == 1 }
        XCTAssertTrue(finished)
        XCTAssertEqual(PendingServer.counts.0, 1)
        XCTAssertTrue(fixture.clipboard.values.isEmpty, "Cancelled dictation must not be copied later")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.audio.path))
    }
    func testPrivacyOffCancelsAnAlreadyPendingPolishAndUsesLocalResult() async throws {
        let fixture = try await fixture()
        try fixture.model.transcribeFile(fixture.audio, temporary: true)
        let started = await eventually { PendingServer.counts.0 == 1 }
        XCTAssertTrue(started)
        fixture.settings.values.polish = false
        let finished = await eventually { !fixture.model.active && PendingServer.counts.1 == 1 }
        XCTAssertTrue(finished)
        XCTAssertEqual(fixture.clipboard.values, ["Hello team."])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.audio.path))
    }
    func testQuitWaitsForPendingWorkAndDeletesTemporaryAudio() async throws {
        let fixture = try await fixture()
        try fixture.model.transcribeFile(fixture.audio, temporary: true)
        let started = await eventually { PendingServer.counts.0 == 1 }
        XCTAssertTrue(started)
        let clean = await fixture.model.shutdown()
        XCTAssertTrue(clean)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.audio.path))
        XCTAssertTrue(fixture.files.temporaryAudio.isEmpty)
        XCTAssertNil(fixture.runtime.workerProcessIdentifier)
        XCTAssertEqual(fixture.runtime.activeWatchdogCount, 0)
        XCTAssertTrue(fixture.clipboard.values.isEmpty)
    }
}
