import Foundation
import Security
import WisprMobileCore
import WisprCore

enum MobilePaths {
    #if DEBUG
    static let integration = ProcessInfo.processInfo.arguments.contains("--integration-audio")
        || ProcessInfo.processInfo.arguments.contains("--integration-restore-check")
    #else
    static let integration = false
    #endif
    private static let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    static let support = base.appendingPathComponent(integration ? "wisprM-Integration" : "wisprM", isDirectory: true)
    // Only reusable model weights are shared with tests; never preferences or transcripts.
    static let models = base.appendingPathComponent("wisprM/Models", isDirectory: true)
    static let recordings = support.appendingPathComponent("Recordings", isDirectory: true)
    static let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TranscriptExchange.appGroup)
    static var exchange: TranscriptExchange? { group.map { TranscriptExchange(directory: $0.appendingPathComponent(integration ? "IntegrationTranscripts" : "Transcripts")) } }
    static let archive = HistoryArchive(file: support.appendingPathComponent("history.json"))
    static func prepare() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        var location = recordings
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try? location.setResourceValues(flags)
        for file in try FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
    }
}

struct ModelReceipt: Codable {
    let relativePath: String
    let bytes: Int64
    var folder: URL? {
        let value = MobilePaths.models.appendingPathComponent(relativePath).standardizedFileURL
        return value.path.hasPrefix(MobilePaths.models.standardizedFileURL.path + "/") ? value : nil
    }
    static func measure(_ directory: URL) throws -> Int64 {
        var total: Int64 = 0
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var count = 0
        for case let file as URL in files {
            try Task.checkCancellation(); count += 1
            guard count <= 25_000 else { throw MobileFailure.message("The model folder contains too many files.") }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
}

enum MobileCredentialStore {
    private static let service = "com.wisprm.mobile.polishing"
    static func read(endpoint: String) -> String {
        guard let origin = EndpointOrigin.key(for: endpoint) else { return "" }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: origin,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ key: String, endpoint: String) throws {
        guard let origin = EndpointOrigin.key(for: endpoint) else { throw PolishError.invalidEndpoint }
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: origin]
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw MobileFailure.message("The credential could not be deleted (\(status)).") }
            return
        }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw MobileFailure.message("The credential could not be saved (\(added)).") }
        } else if status != errSecSuccess { throw MobileFailure.message("The credential could not be updated (\(status)).") }
    }
}
