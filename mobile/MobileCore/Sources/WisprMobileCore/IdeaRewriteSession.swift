import Foundation

/// Manual rewriting chooses a provider without enabling automatic polishing.
public enum RewriteProvider: String, CaseIterable, Identifiable, Sendable {
    case appleIntelligence = "Apple Intelligence"
    case local = "On-device language model"
    case server = "Model server"

    public var id: String { rawValue }
    public var polishMode: PolishMode {
        switch self {
        case .appleIntelligence: return .appleIntelligence
        case .local: return .local
        case .server: return .server
        }
    }
    public var requiresForeground: Bool { polishMode.requiresForeground }
}

/// Keeps an unaccepted proposal separate from the current transcript and its one-level Undo.
public struct IdeaRewriteSession: Equatable, Sendable {
    public private(set) var original: String?
    public private(set) var proposal: String?
    public private(set) var isGenerating = false
    private var activeAttempt: UUID?
    private var undoOriginal: String?
    private var undoAccepted: String?

    /// Whitespace-only differences do not count as a newly composed message.
    public var proposalIsUnchanged: Bool {
        guard let original, let proposal else { return false }
        return original.split(whereSeparator: \.isWhitespace) == proposal.split(whereSeparator: \.isWhitespace)
    }

    public init() {}

    @discardableResult
    public mutating func begin(source: String) -> UUID {
        if undoAccepted != source { clearUndo() }
        let attempt = UUID()
        activeAttempt = attempt
        original = source
        proposal = nil
        isGenerating = true
        return attempt
    }

    /// A cancelled or superseded response cannot replace a newer proposal.
    @discardableResult
    public mutating func finish(_ text: String, attempt: UUID, currentText: String) -> Bool {
        guard activeAttempt == attempt else { return false }
        activeAttempt = nil
        isGenerating = false
        guard let original, original == currentText else {
            textChanged()
            return false
        }
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let cleaned = try? LocalPolishingOutput.clean(text, original: original),
              cleaned.utf8.count <= 800_000 else { return false }
        proposal = cleaned
        return true
    }

    /// Dismissing a draft preserves Undo for an already accepted rewrite.
    public mutating func cancel() {
        activeAttempt = nil
        isGenerating = false
        original = nil
        proposal = nil
    }

    public mutating func accept(currentText: String) -> String? {
        guard !isGenerating, let original, let proposal else { return nil }
        guard original == currentText else {
            textChanged()
            return nil
        }
        // Keep unchanged drafts available for comparison and another attempt.
        guard !proposalIsUnchanged else { return nil }
        undoOriginal = original
        undoAccepted = proposal
        cancel()
        return proposal
    }

    public func canUndo(currentText: String) -> Bool {
        undoOriginal != nil && undoAccepted == currentText
    }

    public mutating func undo(currentText: String) -> String? {
        guard canUndo(currentText: currentText), let previous = undoOriginal else { return nil }
        cancel()
        clearUndo()
        return previous
    }

    /// Call for user edits and new dictations, including changes away from and back to the same text.
    public mutating func textChanged() {
        cancel()
        clearUndo()
    }

    private mutating func clearUndo() {
        undoOriginal = nil
        undoAccepted = nil
    }
}
