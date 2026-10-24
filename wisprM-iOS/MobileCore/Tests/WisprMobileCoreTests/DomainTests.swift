import XCTest
@testable import WisprMobileCore

final class DomainTests: XCTestCase {
    func testAppleIntelligenceConsentCannotSwitchProviderOrAcquireConsentAfterCapture() throws {
        let apple = try XCTUnwrap(PolishMode(rawValue: "Apple Intelligence"))
        var captured = MobilePreferences(), live = MobilePreferences()
        live.polishMode = apple
        XCTAssertFalse(MobilePolishingConsent.allows(captured: captured, live: live))
        captured = live
        live.serverEndpoint = "https://unrelated.example/v1/chat/completions"
        live.localTextModel = "unrelated/model"
        XCTAssertTrue(MobilePolishingConsent.allows(captured: captured, live: live))
        for replacement in [PolishMode.off, .local, .server] {
            live.polishMode = replacement
            XCTAssertFalse(MobilePolishingConsent.allows(captured: captured, live: live))
        }
        let restored = try JSONDecoder().decode(MobilePreferences.self, from: JSONEncoder().encode(captured))
        XCTAssertEqual(restored.polishMode, apple)
        XCTAssertEqual(MobilePreferences().polishMode, .off)
    }
    func testPolishingCannotAcquireNewConsentOrSwitchModelsDuringCapture() {
        var captured = MobilePreferences(), live = MobilePreferences()
        live.polishMode = .local
        XCTAssertFalse(MobilePolishingConsent.allows(captured: captured, live: live))
        captured.polishMode = .local
        XCTAssertTrue(MobilePolishingConsent.allows(captured: captured, live: live))
        live.localTextModel = "other/model"
        XCTAssertFalse(MobilePolishingConsent.allows(captured: captured, live: live))
        captured.polishMode = .server; captured.serverEndpoint = "https://example.com/v1/chat/completions"; captured.serverModel = "small"
        live = captured; live.serverEndpoint = "https://other.example/v1/chat/completions"
        XCTAssertFalse(MobilePolishingConsent.allows(captured: captured, live: live))
        live = captured; live.polishMode = .off
        XCTAssertFalse(MobilePolishingConsent.allows(captured: captured, live: live))
    }
    func testPolishingDoesNotExposeReasoningOrIncompleteTags() throws {
        XCTAssertEqual(try LocalPolishingOutput.clean("<think>Private reasoning</think>Clean text.", original: "text"), "Clean text.")
        XCTAssertThrowsError(try LocalPolishingOutput.clean("<think>unfinished", original: "text"))
        XCTAssertThrowsError(try LocalPolishingOutput.clean("<think>reasoning only</think>", original: "text"))
    }
    func testExchangeRejectsExpiredAndFutureTranscripts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = TranscriptExchange(directory: root), now = Date()
        try exchange.publish(.init(text: "Old", date: now.addingTimeInterval(-601), model: "test"))
        XCTAssertNil(try exchange.latest(now: now))
        try exchange.publish(.init(text: "Future", date: now.addingTimeInterval(31), model: "test"))
        XCTAssertNil(try exchange.latest(now: now))
        let valid = Transcript(text: "Hola, world!", date: now, model: "test")
        try exchange.publish(valid)
        XCTAssertEqual(try exchange.latest(now: now), valid)
        try exchange.clear()
        XCTAssertNil(try exchange.latest())
    }
    func testHistoryBoundsAndDeletesSavedText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = HistoryArchive(file: root.appendingPathComponent("history.json"))
        let entries = (0..<40).map { Transcript(text: "\($0)", model: "test") }
        try archive.save(entries)
        XCTAssertEqual(try archive.load(), Array(entries.prefix(30)))
        try archive.clear()
        XCTAssertEqual(try archive.load(), [])
    }
    func testDefaultsAndExactParakeetModel() throws {
        let preferences = MobilePreferences()
        XCTAssertFalse(preferences.historyEnabled)
        XCTAssertEqual(preferences.polishMode, .off)
        XCTAssertEqual(preferences.speechChoice.name, "Whisper Tiny")
        XCTAssertEqual(SpeechChoice.presets.last?.repository, "FluidInference/parakeet-tdt-0.6b-v3-coreml")
        XCTAssertEqual(try JSONDecoder().decode(MobilePreferences.self, from: JSONEncoder().encode(preferences)), preferences)
    }
    func testOversizedExchangeDoesNotOverwriteValidResult() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = TranscriptExchange(directory: root)
        let valid = Transcript(text: "Keep this", model: "test")
        try exchange.publish(valid)
        XCTAssertThrowsError(try exchange.publish(.init(text: String(repeating: "x", count: 800_001), model: "test")))
        XCTAssertEqual(try exchange.latest(), valid)
    }
}
