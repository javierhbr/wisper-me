import XCTest
@testable import WisprMobileCore

final class PrivacyStorageTests: XCTestCase {
    func testModelDirectoryIsExcludedBeforeAssetsAndAfterRecreation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let models = root.appendingPathComponent("Models")
        try BackupExclusion.prepareDirectory(at: models)
        XCTAssertEqual(try exclusionFlag(models), true)
        try Data("weights".utf8).write(to: models.appendingPathComponent("weights.bin"))
        try FileManager.default.removeItem(at: models)
        try BackupExclusion.prepareDirectory(at: models)
        XCTAssertEqual(try exclusionFlag(models), true)
    }

    func testLegacyHistoryIsMigratedWithoutLosingTextAndAtomicRewritesStayExcluded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("history.json")
        let legacy = [Transcript(text: "Keep my history", model: "test")]
        try JSONEncoder().encode(legacy).write(to: file)
        let archive = HistoryArchive(file: file)
        XCTAssertEqual(try archive.load(), legacy)
        XCTAssertEqual(try exclusionFlag(file), true)
        // Simulate an operation that resets the flag: saving must reapply it,
        // even when the original URL has a cached true resource value.
        var resetFile = file
        var flags = URLResourceValues(); flags.isExcludedFromBackup = false
        try resetFile.setResourceValues(flags)
        XCTAssertNotEqual(try exclusionFlag(file), true)
        let updated = [Transcript(text: "New history", model: "test")]
        try archive.save(updated)
        XCTAssertEqual(try archive.load(), updated)
        XCTAssertEqual(try exclusionFlag(file), true)
        XCTAssertNotEqual(try exclusionFlag(root), true, "A generic archive must not exclude unrelated data in its caller's directory")
    }

    func testSharedTranscriptDirectoryAndAtomicResultsAreExcludedAndLegacyTextMigrates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = TranscriptExchange(directory: root.appendingPathComponent("Transcripts"))
        try FileManager.default.createDirectory(at: exchange.directory, withIntermediateDirectories: true)
        let legacy = Transcript(text: "Legacy shared text", model: "test")
        try JSONEncoder().encode(legacy).write(to: exchange.file)
        try exchange.excludeFromBackupsIfPresent()
        XCTAssertEqual(try exchange.latest(), legacy)
        XCTAssertEqual(try exclusionFlag(exchange.directory), true)
        XCTAssertEqual(try exclusionFlag(exchange.file), true)
        let next = Transcript(text: "Replacement shared text", model: "test")
        try exchange.publish(next)
        XCTAssertEqual(try exchange.latest(), next)
        XCTAssertEqual(try exclusionFlag(exchange.directory), true)
        XCTAssertEqual(try exclusionFlag(exchange.file), true)
    }

    func testClipboardExpirationIsAnchoredToCopyTime() {
        let first = Date(timeIntervalSince1970: 1_000)
        let second = first.addingTimeInterval(90)
        XCTAssertEqual(TranscriptClipboardPolicy.expirationDate(copiedAt: first), first.addingTimeInterval(600))
        XCTAssertEqual(TranscriptClipboardPolicy.expirationDate(copiedAt: second), second.addingTimeInterval(600))
        XCTAssertTrue(TranscriptClipboardPolicy.localOnly)
    }

    private func exclusionFlag(_ file: URL) throws -> Bool? {
        var fresh = URL(fileURLWithPath: file.path)
        fresh.removeAllCachedResourceValues()
        return try fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
    }
}
