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
}

struct Preferences: Codable {
    var engine: SpeechEngine = .whisper
    var whisperModel = SpeechEngine.whisper.defaultModel
    var parakeetModel = SpeechEngine.parakeet.defaultModel
    var language = "auto"
    var style: WritingStyle = .natural
    var spokenCommands = false
    var autoInsert = true
    var keepHistory = false
    var polish = false
    var endpoint = "http://localhost:11434/v1/chat/completions"
    var textModel = ""
    var modelID: String {
        get { engine == .whisper ? whisperModel : parakeetModel }
        set { if engine == .whisper { whisperModel = newValue } else { parakeetModel = newValue } }
    }
    init() {}
    enum CodingKeys: String, CodingKey {
        case engine, whisperModel, parakeetModel, language, style, spokenCommands
        case autoInsert, keepHistory, polish, endpoint, textModel
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        engine = try values.decodeIfPresent(SpeechEngine.self, forKey: .engine) ?? .whisper
        whisperModel = try values.decodeIfPresent(String.self, forKey: .whisperModel) ?? SpeechEngine.whisper.defaultModel
        if whisperModel == "mlx-community/whisper-base" { whisperModel = "mlx-community/whisper-base-mlx" }
        if whisperModel == "mlx-community/whisper-small" { whisperModel = "mlx-community/whisper-small-mlx" }
        parakeetModel = try values.decodeIfPresent(String.self, forKey: .parakeetModel) ?? SpeechEngine.parakeet.defaultModel
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        style = try values.decodeIfPresent(WritingStyle.self, forKey: .style) ?? .natural
        spokenCommands = try values.decodeIfPresent(Bool.self, forKey: .spokenCommands) ?? false
        autoInsert = try values.decodeIfPresent(Bool.self, forKey: .autoInsert) ?? true
        keepHistory = try values.decodeIfPresent(Bool.self, forKey: .keepHistory) ?? false
        polish = try values.decodeIfPresent(Bool.self, forKey: .polish) ?? false
        endpoint = try values.decodeIfPresent(String.self, forKey: .endpoint) ?? "http://localhost:11434/v1/chat/completions"
        textModel = try values.decodeIfPresent(String.self, forKey: .textModel) ?? ""
    }
}

@MainActor final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    @Published var values: Preferences { didSet { save() } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "preferences.v1"),
           let values = try? JSONDecoder().decode(Preferences.self, from: data) { self.values = values }
        else { values = Preferences() }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: "preferences.v1") }
    }
}

enum CredentialStore {
    static let service = "com.wisprm.desktop.polishing"
    static func read(for endpoint: String) -> String {
        guard let origin = EndpointOrigin.key(for: endpoint) else { return "" }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: origin,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String, for endpoint: String) throws {
        guard let origin = EndpointOrigin.key(for: endpoint) else { throw PolishError.invalidEndpoint }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: origin]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AppFailure("Keychain could not delete this server's credential (\(status)).") }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw AppFailure("Keychain could not save this server's credential (\(added)).") }
        } else if status != errSecSuccess { throw AppFailure("Keychain could not update this server's credential (\(status)).") }
    }
    // The former unscoped "api-key" account is deliberately never read or sent.
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
