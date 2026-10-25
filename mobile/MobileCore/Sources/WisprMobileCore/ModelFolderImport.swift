import Foundation

public enum ModelFolderImport {
    /// Called off the main thread while the caller holds security-scoped access.
    public static func copy(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        guard try source.resourceValues(forKeys: keys).isSymbolicLink != true else {
            throw MobileFailure.message("Import a model folder, not a symbolic link.")
        }
        var traversalError: Error?
        guard let files = manager.enumerator(at: source, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in traversalError = error; return false }) else {
            throw MobileFailure.message("The model folder could not be opened.")
        }
        var count = 0, bytes: Int64 = 0
        for case let file as URL in files {
            try Task.checkCancellation(); count += 1
            let values = try file.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw MobileFailure.message("Model folders must not contain symbolic links.") }
            if values.isRegularFile == true {
                let length = Int64(values.fileSize ?? 0)
                guard length >= 0, length <= 20_000_000_000 - bytes else { throw MobileFailure.message("The model exceeds the import size limit.") }
                bytes += length
            }
            guard count <= 25_000, bytes <= 20_000_000_000 else { throw MobileFailure.message("The selected model exceeds the import limits.") }
        }
        if let traversalError { throw traversalError }
        guard bytes > 0 else { throw MobileFailure.message("The selected folder is empty.") }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !manager.fileExists(atPath: destination.path) else { throw MobileFailure.message("The import destination already exists.") }
        do {
            try Task.checkCancellation()
            try manager.copyItem(at: source, to: destination)
            try Task.checkCancellation()
        } catch {
            try? manager.removeItem(at: destination); throw error
        }
    }
}
