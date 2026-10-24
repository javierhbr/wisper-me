import XCTest
@testable import WisprMobileCore

final class ModelFolderImportTests: XCTestCase {
    func testCopiesModelDataAndDoesNotOverwriteExistingDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("copy")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: source.appendingPathComponent("model.bin"))
        try ModelFolderImport.copy(from: source, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("model.bin")), Data("weights".utf8))
        XCTAssertThrowsError(try ModelFolderImport.copy(from: source, to: destination))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("model.bin").path))
    }
    func testRejectsSymlinksBeforeCopyingAnything() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("copy")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("private")
        try Data("not a model".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("escape"), withDestinationURL: outside)
        XCTAssertThrowsError(try ModelFolderImport.copy(from: source, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
