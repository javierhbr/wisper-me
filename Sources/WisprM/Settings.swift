import AppKit
import Combine
import Security
import WisprCore

enum AppPaths {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("wisprM")
    static let runtime = support.appendingPathComponent("runtime")
    static let recordings = support.appendingPathComponent("Recordings")
    static var resources: URL {
        let bundled = Bundle.main.resourceURL!.appendingPathComponent("runtime")
        return FileManager.default.fileExists(atPath: bundled.path) ? bundled : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("runtime")
    }
    static func create() {
        for directory in [support, recordings] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        // Remove only this app's abandoned temporary audio from an earlier crash.
        for url in (try? FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "caf" {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

struct Preferences: Codable {
    var engine: SpeechEngine = .whisper
    var whisperModel = SpeechEngine.whisper.defaultModel
    var parakeetModel = SpeechEngine.parakeet.defaultModel
    var language = "auto"
    var style: WritingStyle = .natural
    var autoInsert = true
    var keepHistory = false
    var polish = false
    var endpoint = "http://localhost:11434/v1/chat/completions"
    var textModel = ""
    var modelID: String {
        get { engine == .whisper ? whisperModel : parakeetModel }
        set { if engine == .whisper { whisperModel = newValue } else { parakeetModel = newValue } }
    }
}

@MainActor final class SettingsStore: ObservableObject {
    @Published var values: Preferences { didSet { save() } }
    init() {
        if let data = UserDefaults.standard.data(forKey: "preferences.v1"),
           let values = try? JSONDecoder().decode(Preferences.self, from: data) { self.values = values }
        else { values = Preferences() }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: "preferences.v1") }
    }
}

enum CredentialStore {
    static let service = "com.wisprm.desktop.polishing"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "api-key",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AppFailure("Keychain could not delete the credential (\(status)).") }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw AppFailure("Keychain could not save the credential (\(added)).") }
        } else if status != errSecSuccess { throw AppFailure("Keychain could not update the credential (\(status)).") }
    }
}

struct AppFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let engine: String
}
