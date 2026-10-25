import Foundation
import XCTest
@testable import WisprM

final class LocalDataStoreTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wisprm-storage-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testCompletedAndCancelledAudioOwnershipIsReleased() throws {
        let files = LocalDataStore(root: try root())
        try files.prepare()
        let first = files.recordings.appendingPathComponent("first.caf")
        let second = files.recordings.appendingPathComponent("second.caf")
        try Data("fixture".utf8).write(to: first)
        try Data("fixture".utf8).write(to: second)
        files.trackAudio(first); files.trackAudio(second)
        try files.releaseAudio(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        try files.cleanupAudio()
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(files.temporaryAudio.isEmpty)
    }
    func testDeletionFailurePreservesOwnershipForRetry() throws {
        let root = try root()
        var fail = true
        let files = LocalDataStore(root: root, remove: { url in
            if fail { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        })
        try files.prepare()
        let audio = files.recordings.appendingPathComponent("fixture.caf")
        try Data("fixture".utf8).write(to: audio)
        files.trackAudio(audio)
        XCTAssertThrowsError(try files.cleanupAudio())
        XCTAssertTrue(files.temporaryAudio.contains(audio))
        fail = false
        try files.cleanupAudio()
        XCTAssertTrue(files.temporaryAudio.isEmpty)
    }
    func testHistoryDeletionErrorDoesNotPretendFileIsGone() throws {
        let root = try root()
        let files = LocalDataStore(root: root, remove: { _ in throw CocoaError(.fileWriteNoPermission) })
        try files.prepare()
        try files.saveHistory([HistoryEntry(id: UUID(), date: Date(), text: "fixture", engine: "Whisper")])
        XCTAssertThrowsError(try files.deleteHistory())
        XCTAssertEqual(try files.loadHistory().first?.text, "fixture")
    }
    func testInaccessiblePathIsNotTreatedAsMissing() throws {
        let files = LocalDataStore(root: try root(), remove: { _ in throw CocoaError(.fileReadNoPermission) })
        let unknownAudio = files.recordings.appendingPathComponent("hidden.caf")
        files.trackAudio(unknownAudio)
        XCTAssertThrowsError(try files.releaseAudio(unknownAudio))
        XCTAssertTrue(files.temporaryAudio.contains(unknownAudio))
        XCTAssertThrowsError(try files.deleteHistory())
    }
    func testAlreadyMissingOwnedFileCanReleaseOwnership() throws {
        let files = LocalDataStore(root: try root())
        let gone = files.recordings.appendingPathComponent("gone.caf")
        files.trackAudio(gone)
        try files.releaseAudio(gone)
        try files.deleteHistory()
        XCTAssertTrue(files.temporaryAudio.isEmpty)
    }
    func testHistoryCapAndOwnerOnlyPermissions() throws {
        let files = LocalDataStore(root: try root())
        try files.prepare()
        let entries = (0..<40).map { HistoryEntry(id: UUID(), date: Date(), text: "entry \($0)", engine: "Whisper") }
        try files.saveHistory(entries)
        XCTAssertEqual(try files.loadHistory().count, 30)
        let mode = try FileManager.default.attributesOfItem(atPath: files.historyURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual((mode?.intValue ?? 0) & 0o777, 0o600)
    }
    func testChunkCleanupDoesNotDeleteImportedOrUnownedAudio() throws {
        let files = LocalDataStore(root: try root())
        try files.prepare()
        let chunk = files.recordings.appendingPathComponent("wisprm-chunk-fixture.wav")
        let unowned = files.recordings.appendingPathComponent("imported.wav")
        try Data("fixture".utf8).write(to: chunk)
        try Data("fixture".utf8).write(to: unowned)
        try files.cleanupAudio()
        XCTAssertFalse(FileManager.default.fileExists(atPath: chunk.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unowned.path))
    }
}
