import Foundation
import XCTest
@testable import WisprM

final class ModelStorageTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/example")

    func testHubCacheEnvironmentPrecedence() {
        XCTAssertEqual(SpeechModelCatalog.cacheRoot(environment: [:], home: home).path,
                       "/Users/example/.cache/huggingface/hub")
        XCTAssertEqual(SpeechModelCatalog.cacheRoot(environment: ["XDG_CACHE_HOME": "/cache"], home: home).path,
                       "/cache/huggingface/hub")
        XCTAssertEqual(SpeechModelCatalog.cacheRoot(environment: ["HF_HOME": "~/models", "XDG_CACHE_HOME": "/cache"], home: home).path,
                       "/Users/example/models/hub")
        XCTAssertEqual(SpeechModelCatalog.cacheRoot(environment: ["HF_HUB_CACHE": "/hub", "HF_HOME": "/ignored"], home: home).path,
                       "/hub")
        XCTAssertEqual(SpeechModelCatalog.cacheRoot(environment: ["HUGGINGFACE_HUB_CACHE": "/legacy"], home: home).path,
                       "/legacy")
    }

    func testPinnedPresetsHaveSizesAndRevisionLocations() {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("runtime/models.lock.json")
        let catalog = SpeechModelCatalog(url: source)
        let expected: [String: Int64] = [
            "mlx-community/whisper-tiny": 74_418_670,
            "mlx-community/whisper-base-mlx": 143_724_807,
            "mlx-community/whisper-small-mlx": 481_308_201,
            "mlx-community/parakeet-tdt-0.6b-v3": 2_508_533_910
        ]
        for (id, size) in expected {
            XCTAssertEqual(catalog.entries[id]?.downloadBytes, size)
            let path = catalog.location(for: id, environment: [:], home: home)?.path
            XCTAssertTrue(path?.hasSuffix("snapshots/" + catalog.entries[id]!.revision) == true)
        }
        XCTAssertEqual(catalog.downloadSize("example/custom"), "Download size unknown")
        XCTAssertNil(catalog.location(for: "../invalid/path", environment: [:], home: home))
        XCTAssertEqual(catalog.location(for: "~/my-model", environment: [:], home: home)?.path, "/Users/example/my-model")
    }

    func testCustomPinnedAndCachedMainLocations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let revision = String(repeating: "a", count: 40)
        let refs = root.appendingPathComponent("models--example--custom/refs")
        try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
        try revision.write(to: refs.appendingPathComponent("main"), atomically: true, encoding: .utf8)
        let catalog = SpeechModelCatalog(url: root.appendingPathComponent("missing.json"))
        let environment = ["HF_HUB_CACHE": root.path]
        let expected = root.appendingPathComponent("models--example--custom/snapshots/" + revision)
        XCTAssertEqual(catalog.location(for: "example/custom", environment: environment), expected)
        XCTAssertEqual(catalog.location(for: "example/custom@" + revision, environment: environment), expected)
    }

    func testStorageMeasuresSymlinkTargetsAndDoesNotCallPartialCacheComplete() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = root.appendingPathComponent("snapshot")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        let missing = ModelStorageStatus.inspect(location: root.appendingPathComponent("absent"), engine: .whisper)
        XCTAssertFalse(missing.exists)
        XCTAssertNil(missing.bytes)
        try Data("{}".utf8).write(to: snapshot.appendingPathComponent("config.json"))
        XCTAssertFalse(ModelStorageStatus.inspect(location: snapshot, engine: .whisper).complete)
        let blob = root.appendingPathComponent("blob")
        try Data(repeating: 0, count: 4096).write(to: blob)
        try FileManager.default.createSymbolicLink(at: snapshot.appendingPathComponent("weights.npz"), withDestinationURL: blob)
        let complete = ModelStorageStatus.inspect(location: snapshot, engine: .whisper)
        XCTAssertTrue(complete.exists)
        XCTAssertTrue(complete.complete)
        XCTAssertEqual(complete.bytes, 4098)
        XCTAssertFalse(ModelStorageStatus.inspect(location: snapshot, engine: .parakeet).complete)
    }
}
