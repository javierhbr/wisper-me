import Foundation
import WisprCore

/// Metadata belongs to the same pinned revisions used by the Python worker.
struct SpeechModelCatalog {
    static let bundled = SpeechModelCatalog()
    struct Entry: Decodable {
        let revision: String
        let downloadBytes: Int64?
        enum CodingKeys: String, CodingKey {
            case revision
            case downloadBytes = "download_bytes"
        }
    }
    private struct Manifest: Decodable { let models: [String: Entry] }
    let entries: [String: Entry]

    init(url: URL = AppPaths.resources.appendingPathComponent("models.lock.json")) {
        entries = (try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).models) ?? [:]
    }

    static let whisperPresets = [
        (name: "Tiny", id: "mlx-community/whisper-tiny"),
        (name: "Base", id: "mlx-community/whisper-base-mlx"),
        (name: "Small", id: "mlx-community/whisper-small-mlx")
    ]

    func downloadSize(_ model: String) -> String {
        guard let bytes = entry(model)?.downloadBytes else { return "Download size unknown" }
        return Self.size(bytes) + " download"
    }

    var whisperDownloadRange: String {
        guard let first = entries[Self.whisperPresets[0].id]?.downloadBytes,
              let last = entries[Self.whisperPresets[2].id]?.downloadBytes else { return "Download sizes unknown" }
        return "Presets: " + Self.size(first) + " – " + Self.size(last) + " download"
    }

    private func entry(_ model: String) -> Entry? {
        let parts = model.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count <= 2, let repository = parts.first, let entry = entries[String(repository)],
              parts.count == 1 || parts[1].lowercased() == entry.revision.lowercased() else { return nil }
        return entry
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func cacheRoot(environment: [String: String], home: URL) -> URL {
        func url(_ path: String) -> URL {
            let expanded = path == "~" ? home.path : path.hasPrefix("~/") ? home.path + String(path.dropFirst()) : path
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        if let path = environment["HF_HUB_CACHE"] ?? environment["HUGGINGFACE_HUB_CACHE"] { return url(path) }
        if let path = environment["HF_HOME"] { return url(path).appendingPathComponent("hub") }
        let base = environment["XDG_CACHE_HOME"].map(url) ?? home.appendingPathComponent(".cache")
        return base.appendingPathComponent("huggingface/hub")
    }

    func location(for model: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                  home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.hasPrefix("/") { return URL(fileURLWithPath: model, isDirectory: true) }
        if model == "~" || model.hasPrefix("~/") {
            return URL(fileURLWithPath: home.path + String(model.dropFirst()), isDirectory: true)
        }
        let parts = model.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count <= 2, let repository = parts.first,
              repository.range(of: #"^[\w.-]+/[\w.-]+$"#, options: .regularExpression) != nil else { return nil }
        var revision = entry(model)?.revision ?? (parts.count == 2 ? String(parts[1]) : nil)
        let repositoryPath = Self.cacheRoot(environment: environment, home: home)
            .appendingPathComponent("models--" + repository.replacingOccurrences(of: "/", with: "--"))
        if revision == nil, parts.count == 1 {
            revision = (try? String(contentsOf: repositoryPath.appendingPathComponent("refs/main"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let revision, revision.range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil {
            return repositoryPath.appendingPathComponent("snapshots/" + revision)
        }
        return repositoryPath
    }
}

struct ModelStorageStatus: Sendable {
    let location: URL?
    let exists: Bool
    let complete: Bool
    let bytes: Int64?

    static func inspect(location: URL?, engine: SpeechEngine) -> Self {
        guard let location else { return Self(location: nil, exists: false, complete: false, bytes: nil) }
        let manager = FileManager.default
        var directory: ObjCBool = false
        let exists = manager.fileExists(atPath: location.path, isDirectory: &directory) && directory.boolValue
        let weights = engine == .whisper ? ["weights.npz", "weights.safetensors"] : ["model.safetensors"]
        let complete = exists && manager.fileExists(atPath: location.appendingPathComponent("config.json").path)
            && weights.contains { manager.fileExists(atPath: location.appendingPathComponent($0).path) }
        var total: Int64 = 0
        var measured = exists
        if exists {
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
            var failed = false
            let enumerator = manager.enumerator(at: location, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles], errorHandler: { _, _ in failed = true; return false })
            var count = 0
            if let enumerator {
                while let file = enumerator.nextObject() as? URL {
                    count += 1
                    if Task.isCancelled || count > 20_000 { measured = false; break }
                    // Hub snapshots contain symlinks to shared blobs. Count target file bytes.
                    guard let values = try? file.resolvingSymlinksInPath().resourceValues(forKeys: Set(keys)) else {
                        measured = false; continue
                    }
                    if values.isRegularFile == true {
                        if let size = values.fileSize {
                            let sum = total.addingReportingOverflow(Int64(size))
                            if sum.overflow { measured = false; break }
                            total = sum.partialValue
                        } else { measured = false }
                    }
                }
            } else { measured = false }
            if failed { measured = false }
        }
        return Self(location: location, exists: exists, complete: complete, bytes: measured ? total : nil)
    }
}
