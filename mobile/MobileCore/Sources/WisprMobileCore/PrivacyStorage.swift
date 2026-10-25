import Foundation
#if os(iOS)
import UIKit
#endif

/// Mark owned, reproducible or device-private data before populating it. This is
/// the OS backup-exclusion policy flag; it does not erase previous backups.
public enum BackupExclusion {
    public static func prepareDirectory(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try exclude(directory)
    }

    public static func exclude(_ item: URL) throws {
        var location = item
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        // Reapply after atomic replacement; a cached resource value can refer to
        // the old inode and must not be used to skip this write.
        try location.setResourceValues(values)
    }
}

public enum TranscriptClipboardPolicy {
    public static let localOnly = true
    public static let lifetime: TimeInterval = 600

    public static func expirationDate(copiedAt: Date = Date()) -> Date {
        copiedAt.addingTimeInterval(lifetime)
    }

    #if os(iOS)
    @MainActor public static func copy(_ text: String, copiedAt: Date = Date()) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.setObjects([text], localOnly: localOnly,
            expirationDate: expirationDate(copiedAt: copiedAt))
    }
    #endif
}
