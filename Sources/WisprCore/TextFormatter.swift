import Foundation

public enum WritingStyle: String, CaseIterable, Codable, Sendable {
    case natural = "Natural", professional = "Professional", casual = "Casual", bullets = "Bullet points"
}
public struct TextFormatter: Sendable {
    public init() {}
    public func format(_ input: String, style: WritingStyle = .natural, locale: String = "en-US") -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if locale.hasPrefix("en") {
            for (phrase, replacement) in [
                ("new paragraph", "\n\n"), ("new line", "\n"), ("question mark", "?"),
                ("exclamation (?:mark|point)", "!"), ("full stop", "."),
                ("comma", ","), ("semicolon", ";"), ("colon", ":")
            ] { text = replace(text, "\\b\(phrase)\\b[,.]?", replacement) }
            text = replace(text, "\\b(?:um+|uh+|erm+)\\b[,;]?", "")
            text = replace(text, "\\bi\\b", "I")
        }
        text = replace(text, "[\\t ]+", " ")
        text = replace(text, " *\\n *", "\n")
        text = replace(text, " +([,.;:!?])", "$1")
        text = replace(text, "([,;:!?])(?=[\\p{L}])", "$1 ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if style == .bullets {
            return text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                .map { "• " + capitalize($0.replacingOccurrences(of: "^[•\\-] +", with: "", options: .regularExpression)) }
                .joined(separator: "\n")
        }
        text = text.components(separatedBy: "\n").map(capitalize).joined(separator: "\n")
        if let expression = try? NSRegularExpression(pattern: "(?<=[.!?] )\\p{Ll}") {
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                if let range = Range(match.range, in: text) { text.replaceSubrange(range, with: text[range].uppercased()) }
            }
        }
        if style != .casual, let last = text.last, last.isLetter || last.isNumber { text += "." }
        return text
    }
    private func capitalize(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
    private func replace(_ text: String, _ pattern: String, _ replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
    }
}
public enum EndpointPolicy {
    public static func validate(_ value: String) -> URL? {
        guard let parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let url = parts.url else { return nil }
        let loopback = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)
        guard parts.scheme == "https" || (parts.scheme == "http" && loopback) else { return nil }
        return url
    }
}
public enum SpeechEngine: String, CaseIterable, Codable, Sendable {
    case whisper = "Whisper", parakeet = "Parakeet"
    public var defaultModel: String {
        self == .whisper ? "mlx-community/whisper-tiny" : "mlx-community/parakeet-tdt-0.6b-v3"
    }
    public var detail: String {
        self == .whisper ? "Tiny / Base / Small · multilingual" : "TDT v3 · 0.6B parameters · multilingual"
    }
}
