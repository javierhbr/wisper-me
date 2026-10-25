import Foundation

public enum WritingStyle: String, CaseIterable, Codable, Sendable {
    case natural = "Natural", professional = "Professional", casual = "Casual", bullets = "Bullet points"
}
public struct TextFormatter: Sendable {
    public init() {}

    public func format(_ input: String, style: WritingStyle = .natural, locale: String = "en-US",
                       interpretCommands: Bool = false) -> String {
        let protected = protectStructuredSpans(input.trimmingCharacters(in: .whitespacesAndNewlines))
        var text = protected.text
        guard !text.isEmpty else { return "" }
        if locale.hasPrefix("en") {
            if interpretCommands {
                for (phrase, replacement) in [
                    ("new paragraph", "\n\n"), ("new line", "\n"), ("question mark", "?"),
                    ("exclamation (?:mark|point)", "!"), ("full stop", "."),
                    ("comma", ","), ("semicolon", ";"), ("colon", ":")
                ] {
                    text = replace(text, "\\b\(phrase)\\b[,.]?", replacement, ignoreCase: true)
                }
            }
            // Keep uppercase abbreviations such as UM intact.
            text = replace(text, "\\b(?:[Uu]m+|[Uu]h+|[Ee]rm+)\\b[,;]?", "")
            text = replace(text, "\\bi\\b", "I")
        }
        text = replace(text, "[\\t ]+", " ")
        text = replace(text, " *\\n *", "\n")
        text = replace(text, " +([,.;:!?])", "$1")
        text = replace(text, "([,;:!?])(?=[\\p{L}])", "$1 ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if style == .bullets {
            text = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                .map { "• " + capitalizeSentences($0.replacingOccurrences(of: "^[•\\-] +", with: "", options: .regularExpression)) }
                .joined(separator: "\n")
        } else {
            text = capitalizeSentences(text)
            // A protected URL, address, path, or code span is already complete as supplied.
            if style != .casual, let last = text.last, last.isLetter || last.isNumber { text += "." }
        }
        for (marker, original) in protected.spans { text = text.replacingOccurrences(of: marker, with: original) }
        return text
    }

    private func capitalizeSentences(_ value: String) -> String {
        var text = value
        let pattern = "(^|[.!?][ \\t]+|\\n)(\\p{Ll}[\\p{L}\\p{N}_]*)"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range(at: 2), in: text) else { continue }
            let word = String(text[range])
            // iPhone, eBay, and other deliberately mixed-case names are not sentence-case words.
            guard !word.dropFirst().contains(where: \.isUppercase), let first = word.first else { continue }
            text.replaceSubrange(range, with: first.uppercased() + word.dropFirst())
        }
        return text
    }

    private func protectStructuredSpans(_ text: String) -> (text: String, spans: [(String, String)]) {
        let tick = "\u{0060}"
        let pattern = "(?s)\(tick){3}.*?\(tick){3}|\(tick)[^\(tick)\\n]+\(tick)"
            + "|(?i:\\b[a-z][a-z0-9+.-]*://[^\\s<>]+|\\bwww\\.[^\\s<>]+)"
            + "|(?i:[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,})"
            + "|(?i:\\b(?:[a-z0-9-]+\\.)+[a-z]{2,}(?::[0-9]+)?(?:[/\\?#][^\\s<>]*)?)"
            + "|(?<![\\p{L}\\p{N}])(?:~?/|\\.\\.?/|[A-Za-z]:\\\\)[^\\s<>]+"
            + "|\\b[\\p{L}\\p{N}_.-]+(?:/[\\p{L}\\p{N}_.@+%~-]+)+"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return (text, []) }
        var masked = text
        var spans: [(String, String)] = []
        let tag = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: masked) else { continue }
            let marker = "\u{E000}\(tag)X\(spans.count)\u{E001}"
            spans.append((marker, String(masked[range])))
            masked.replaceSubrange(range, with: marker)
        }
        return (masked, spans)
    }

    private func replace(_ text: String, _ pattern: String, _ replacement: String, ignoreCase: Bool = false) -> String {
        let options: String.CompareOptions = ignoreCase ? [.regularExpression, .caseInsensitive] : [.regularExpression]
        return text.replacingOccurrences(of: pattern, with: replacement, options: options)
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
        self == .whisper ? "Tiny / Base / Small · multilingual" : "TDT 0.6B v3 · multilingual"
    }
}
