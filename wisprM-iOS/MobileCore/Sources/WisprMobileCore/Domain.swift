import Foundation
import WisprCore

public struct SpeechChoice: Codable, Identifiable, Equatable, Sendable {
    public enum Engine: String, Codable, Sendable { case whisper, parakeet }
    public let id: String
    public let name: String
    public let engine: Engine
    public let repository: String
    public let variant: String
    /// Native Core ML file metadata checked on 2026-10-23; tokenizer/cache overhead varies.
    public var estimatedDownloadBytes: Int64? {
        switch id {
        case "whisper-tiny": return 76_635_397
        case "whisper-base": return 146_719_453
        case "whisper-small": return 486_487_465
        case "parakeet-v3": return 483_105_645
        default: return nil
        }
    }
    public static let presets: [Self] = [
        .init(id: "whisper-tiny", name: "Whisper Tiny", engine: .whisper, repository: "argmaxinc/whisperkit-coreml", variant: "openai_whisper-tiny"),
        .init(id: "whisper-base", name: "Whisper Base", engine: .whisper, repository: "argmaxinc/whisperkit-coreml", variant: "openai_whisper-base"),
        .init(id: "whisper-small", name: "Whisper Small", engine: .whisper, repository: "argmaxinc/whisperkit-coreml", variant: "openai_whisper-small"),
        .init(id: "parakeet-v3", name: "Parakeet TDT 0.6B v3", engine: .parakeet, repository: "FluidInference/parakeet-tdt-0.6b-v3-coreml", variant: "v3-int8")
    ]
    public init(id: String, name: String, engine: Engine, repository: String, variant: String) {
        self.id = id; self.name = name; self.engine = engine; self.repository = repository; self.variant = variant
    }
}

public enum PolishMode: String, Codable, CaseIterable, Sendable {
    case off = "Local cleanup only", local = "On-device language model", server = "Model server"
}

public struct MobilePreferences: Codable, Equatable, Sendable {
    public var modelID = SpeechChoice.presets[0].id
    public var language = "auto"
    public var style = WritingStyle.natural
    public var spokenCommands = false
    public var historyEnabled = false
    public var polishMode = PolishMode.off
    public var localTextModel = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    public var localTextFolder: String?
    public var customSpeechChoice: SpeechChoice?
    public var serverEndpoint = ""
    public var serverModel = ""
    public init() {}
    public var speechChoice: SpeechChoice {
        if let customSpeechChoice, customSpeechChoice.id == modelID { return customSpeechChoice }
        return SpeechChoice.presets.first { $0.id == modelID } ?? SpeechChoice.presets[0]
    }
}

public struct Transcript: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let date: Date
    public let model: String
    public init(id: UUID = UUID(), text: String, date: Date = Date(), model: String) {
        self.id = id; self.text = text; self.date = date; self.model = model
    }
}

public enum MobileFailure: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}

public enum LocalPolishingOutput {
    public static func clean(_ input: String, original: String) throws -> String {
        let complete = try NSRegularExpression(pattern: "(?is)<think>.*?</think>")
        let range = NSRange(input.startIndex..., in: input)
        let output = complete.stringByReplacingMatches(in: input, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.range(of: #"(?is)<\s*/?\s*think\b"#, options: .regularExpression) == nil,
              !output.isEmpty, output.count <= max(16_000, original.count * 6) else {
            throw MobileFailure.message("The text model returned an unusable response. Local cleanup was kept.")
        }
        return output
    }
}

public enum MobilePolishingConsent {
    public static func allows(captured: MobilePreferences, live: MobilePreferences) -> Bool {
        guard captured.polishMode != .off, captured.polishMode == live.polishMode else { return false }
        if captured.polishMode == .local { return captured.localTextModel == live.localTextModel && captured.localTextFolder == live.localTextFolder }
        return PolishingConsent.allows(capturedEnabled: true, liveEnabled: true,
            capturedEndpoint: captured.serverEndpoint, liveEndpoint: live.serverEndpoint)
            && captured.serverModel == live.serverModel
    }
}

/// No desktop assumptions and no microphone/network access: also used by the keyboard.
public struct TranscriptExchange: Sendable {
    public static var appGroup: String { Bundle.main.object(forInfoDictionaryKey: "WisprAppGroup") as? String ?? "group.com.wisprm.mobile" }
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public var file: URL { directory.appendingPathComponent("latest-transcript.json") }
    public func publish(_ transcript: Transcript) throws {
        guard !transcript.text.isEmpty, transcript.text.utf8.count <= 800_000 else {
            throw MobileFailure.message("The transcript is empty or too large to share.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(transcript).write(to: file, options: .atomic)
        var location = directory
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try? location.setResourceValues(flags)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        #endif
    }
    public func latest(now: Date = Date(), maximumAge: TimeInterval = 600) throws -> Transcript? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let size = (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size <= 1_000_000 else { throw MobileFailure.message("The shared transcript exceeds the size limit.") }
        let value = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: file))
        guard !value.text.isEmpty, value.text.utf8.count <= 800_000,
              value.date.timeIntervalSince(now) <= 30,
              now.timeIntervalSince(value.date) <= maximumAge else { return nil }
        return value
    }
    public func clear() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

public struct HistoryArchive: Sendable {
    public let file: URL
    public init(file: URL) { self.file = file }
    public func load() throws -> [Transcript] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let count = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard count <= 2_000_000 else { throw MobileFailure.message("Saved history exceeds the size limit.") }
        return Array(try JSONDecoder().decode([Transcript].self, from: Data(contentsOf: file)).prefix(30))
    }
    public func save(_ values: [Transcript]) throws {
        var bounded = Array(values.prefix(30))
        var data = try JSONEncoder().encode(bounded)
        while !bounded.isEmpty && data.count > 2_000_000 {
            bounded.removeLast(); data = try JSONEncoder().encode(bounded)
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        #endif
    }
    public func clear() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
