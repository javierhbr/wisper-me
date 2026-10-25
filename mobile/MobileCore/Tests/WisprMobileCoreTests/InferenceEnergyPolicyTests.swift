import XCTest
@testable import WisprMobileCore

final class InferenceEnergyPolicyTests: XCTestCase {
    func testForegroundReturnDoesNotSpeculativelyReloadModels() {
        XCTAssertFalse(InferenceEnergyPolicy.shouldPreloadSpeech(trigger: .dictateSelected, dictateVisible: true, pressure: .constrained))
        XCTAssertFalse(InferenceEnergyPolicy.shouldPreloadSpeech(trigger: .foregroundReturn,
            dictateVisible: true, pressure: .normal))
        XCTAssertFalse(InferenceEnergyPolicy.shouldPreloadSpeech(trigger: .coldLaunch,
            dictateVisible: false, pressure: .normal))
        XCTAssertTrue(InferenceEnergyPolicy.shouldPreloadSpeech(trigger: .coldLaunch,
            dictateVisible: true, pressure: .normal))
        XCTAssertTrue(InferenceEnergyPolicy.shouldPreloadSpeech(trigger: .dictateSelected,
            dictateVisible: true, pressure: .normal))
        XCTAssertFalse(InferenceEnergyPolicy.shouldPreloadSpeech(trigger: .coldLaunch,
            dictateVisible: true, pressure: .critical))
    }

    func testAppleRetainsSpeechOnlyWhenForegroundResourcesPermitIt() {
        XCTAssertTrue(InferenceEnergyPolicy.retainSpeechForApple(foreground: true, pressure: .normal))
        XCTAssertFalse(InferenceEnergyPolicy.retainSpeechForApple(foreground: false, pressure: .normal))
        XCTAssertFalse(InferenceEnergyPolicy.retainSpeechForApple(foreground: true, pressure: .constrained))
        XCTAssertFalse(InferenceEnergyPolicy.retainSpeechForApple(foreground: true, pressure: .critical))
        XCTAssertTrue(InferenceEnergyPolicy.cancelPolishing(mode: .local, pressure: .constrained))
        XCTAssertFalse(InferenceEnergyPolicy.cancelPolishing(mode: .appleIntelligence, pressure: .constrained))
        XCTAssertTrue(InferenceEnergyPolicy.cancelPolishing(mode: .appleIntelligence, pressure: .critical))
        XCTAssertFalse(InferenceEnergyPolicy.cancelPolishing(mode: .server, pressure: .critical))
    }

    func testReceiptCanBeReusedOnlyForTheSameValidatedCacheFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("weights", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(InferenceEnergyPolicy.reuseReceipt(recordedFolder: folder,
            cachedFolder: folder, loadedFolder: folder, bytes: 100))
        XCTAssertFalse(InferenceEnergyPolicy.reuseReceipt(recordedFolder: folder,
            cachedFolder: nil, loadedFolder: folder, bytes: 100))
        XCTAssertFalse(InferenceEnergyPolicy.reuseReceipt(recordedFolder: folder,
            cachedFolder: folder, loadedFolder: root.appendingPathComponent("other"), bytes: 100))
        XCTAssertFalse(InferenceEnergyPolicy.reuseReceipt(recordedFolder: folder,
            cachedFolder: folder, loadedFolder: folder, bytes: -1))
    }
}
