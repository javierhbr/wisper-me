import Foundation

/// Owns only wisprM's local history and explicitly registered temporary recordings.
final class LocalDataStore {
    let root: URL
    var recordings: URL { root.appendingPathComponent("Recordings") }
    var historyURL: URL { root.appendingPathComponent("history.json") }
    private(set) var temporaryAudio = Set<URL>()
    private let remove: (URL) throws -> Void

    init(root: URL = AppPaths.support, remove: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.root = root; self.remove = remove
    }
    func prepare(cleanStaleAudio: Bool = true) throws {
        for path in [root, recordings] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
        }
        if cleanStaleAudio {
            for path in try FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)
                where path.pathExtension == "caf" || (path.lastPathComponent.hasPrefix("wisprm-chunk-") && path.pathExtension == "wav") {
                try remove(path)
            }
        }
    }
    func trackAudio(_ url: URL) { temporaryAudio.insert(url) }
    func releaseAudio(_ url: URL) throws {
        guard temporaryAudio.contains(url) else { return }
        do { try remove(url) }
        catch { if !Self.isMissing(error) { throw error } }
        temporaryAudio.remove(url)
    }
    func cleanupAudio() throws {
        var firstError: Error?
        for url in temporaryAudio {
            do { try releaseAudio(url) } catch { firstError = firstError ?? error }
        }
        do {
            for url in try FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)
                where url.lastPathComponent.hasPrefix("wisprm-chunk-") && url.pathExtension == "wav" {
                do { try remove(url) } catch { if !Self.isMissing(error) { firstError = firstError ?? error } }
            }
        } catch { if !Self.isMissing(error) { firstError = firstError ?? error } }
        if let firstError { throw firstError }
    }
    func loadHistory() throws -> [HistoryEntry] {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: historyURL.path) }
        catch { if Self.isMissing(error) { return [] }; throw error }
        let bytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard bytes <= 2_000_000 else { throw AppFailure("Saved history exceeds the supported size. Delete it from Settings.") }
        return Array(try JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: historyURL)).prefix(30))
    }
    func saveHistory(_ entries: [HistoryEntry]) throws {
        let data = try JSONEncoder().encode(Array(entries.prefix(30)))
        guard data.count <= 2_000_000 else { throw AppFailure("History exceeds its local storage limit.") }
        try data.write(to: historyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
    }
    var mayHaveHistory: Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: historyURL.path); return true }
        catch { return !Self.isMissing(error) }
    }
    func deleteHistory() throws {
        do { try remove(historyURL) }
        catch { if !Self.isMissing(error) { throw error } }
    }
    private static func isMissing(_ error: Error) -> Bool {
        let value = error as NSError
        return (value.domain == NSCocoaErrorDomain
                && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(value.code))
            || (value.domain == NSPOSIXErrorDomain && value.code == Int(ENOENT))
    }
}
