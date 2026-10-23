import XCTest
@testable import WisprCore

final class SessionPolicyTests: XCTestCase {
    let first = "https://first.example/v1/chat/completions"
    let second = "https://second.example/v1/chat/completions"
    func testPrivacyOffRevokesCapturedConsent() {
        XCTAssertTrue(PolishingConsent.allows(capturedEnabled: true, liveEnabled: true, capturedEndpoint: first, liveEndpoint: first))
        XCTAssertFalse(PolishingConsent.allows(capturedEnabled: true, liveEnabled: false, capturedEndpoint: first, liveEndpoint: first))
        XCTAssertFalse(PolishingConsent.allows(capturedEnabled: false, liveEnabled: true, capturedEndpoint: first, liveEndpoint: first))
    }
    func testPrivacyOffControlStaysEnabledEvenWhileRuntimeIsBusy() {
        XCTAssertTrue(PolishingConsent.canChangeToggle(currentEnabled: true, sessionActive: true, runtimeBusy: true))
        XCTAssertTrue(PolishingConsent.canChangeToggle(currentEnabled: true, sessionActive: false, runtimeBusy: true))
        XCTAssertFalse(PolishingConsent.canChangeToggle(currentEnabled: false, sessionActive: true, runtimeBusy: true))
        XCTAssertTrue(PolishingConsent.canChangeToggle(currentEnabled: false, sessionActive: false, runtimeBusy: false))
    }
    func testDestinationChangeCannotAcquireConsent() {
        XCTAssertFalse(PolishingConsent.allows(capturedEnabled: true, liveEnabled: true, capturedEndpoint: first, liveEndpoint: second))
        XCTAssertFalse(PolishingConsent.allows(capturedEnabled: true, liveEnabled: true, capturedEndpoint: "invalid", liveEndpoint: "invalid"))
    }
    func testAudioImportFormatsAndSizeAreBounded() {
        XCTAssertTrue(AudioImportPolicy.accepts(fileExtension: "MP3", bytes: 1024))
        XCTAssertTrue(AudioImportPolicy.accepts(fileExtension: "flac", bytes: AudioImportPolicy.maximumBytes))
        XCTAssertFalse(AudioImportPolicy.accepts(fileExtension: "midi", bytes: 1024))
        XCTAssertFalse(AudioImportPolicy.accepts(fileExtension: "wav", bytes: AudioImportPolicy.maximumBytes + 1))
        XCTAssertFalse(AudioImportPolicy.accepts(fileExtension: "wav", bytes: -1))
    }
    func testUnknownAndSecureFieldsFailClosed() {
        XCTAssertTrue(InsertionEligibility.allows(role: "AXTextField", subrole: ""))
        XCTAssertTrue(InsertionEligibility.allows(role: "AXTextArea", subrole: "AXStandardWindow"))
        XCTAssertFalse(InsertionEligibility.allows(role: "AXTextField", subrole: "AXSecureTextField"))
        XCTAssertFalse(InsertionEligibility.allows(role: nil, subrole: ""))
        XCTAssertFalse(InsertionEligibility.allows(role: "AXTextField", subrole: nil))
        XCTAssertFalse(InsertionEligibility.allows(role: "AXButton", subrole: ""))
    }
}
