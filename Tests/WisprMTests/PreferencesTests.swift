import Foundation
import XCTest
@testable import WisprM

final class PreferencesTests: XCTestCase {
    func testOldPreferencesMigrateWithoutResettingPrivacyChoices() throws {
        let old = Data(#"{"engine":"Parakeet","autoInsert":false,"keepHistory":true,"polish":false,"endpoint":"http://localhost:1234/v1/chat/completions"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertEqual(preferences.engine.rawValue, "Parakeet")
        XCTAssertFalse(preferences.autoInsert)
        XCTAssertTrue(preferences.keepHistory)
        XCTAssertFalse(preferences.polish)
        XCTAssertFalse(preferences.spokenCommands)
        XCTAssertEqual(preferences.endpoint, "http://localhost:1234/v1/chat/completions")
    }
    func testCorrectedWhisperPresetAliasesMigrate() throws {
        let old = Data(#"{"whisperModel":"mlx-community/whisper-small"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertEqual(preferences.whisperModel, "mlx-community/whisper-small-mlx")
    }
}
