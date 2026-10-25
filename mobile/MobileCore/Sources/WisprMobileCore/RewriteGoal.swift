import Foundation

/// Requested rewriting goals remain separate from provider selection and publication.
public enum RewriteGoal: String, CaseIterable, Identifiable, Sendable {
    case defaultClarity = "Default"
    case mainPointFirst = "Main point first"
    case clearStory = "Tell a clear story"
    case professional = "Professional message"
    case custom = "Custom"

    public var id: String { rawValue }

    public var explanation: String {
        switch self {
        case .defaultClarity:
            return "Reorder ideas, improve transitions, and remove repetition while preserving the message."
        case .mainPointFirst:
            return "Start with the main point, then organize the supporting details and next steps."
        case .clearStory:
            return "Organize stated events and context into a clear story without inventing a timeline or causes."
        case .professional:
            return "Use clear, concise wording for work while preserving details, uncertainty, and intention."
        case .custom:
            return "Describe the structure or wording you want. The preservation rules still apply."
        }
    }

    public func directions(custom: String) -> String {
        let goal: String
        switch self {
        case .defaultClarity:
            goal = """
            Reorder ideas, improve transitions, and remove genuine repetition.
            Recompose the explanation beyond grammar correction; use clearer
            organization and fresh phrasing rather than merely copying the source.
            """
        case .mainPointFirst:
            goal = """
            Put the main point first, then group related supporting details,
            secondary updates, and next steps in a clear order. Improve transitions
            and remove genuine repetition without discarding any distinct point.
            """
        case .clearStory:
            goal = """
            Arrange stated events and context into a coherent narrative with clear
            transitions. Follow a timeline only when the source establishes one.
            Do not invent chronology, causality, or dialogue, and do not add scenes,
            events, or motivations. Retain every distinct update and requested action.
            """
        case .professional:
            goal = """
            Recompose as a concise, clear professional message appropriate for work.
            Organize the existing context, issues, updates, and next steps.
            Do not invent a recipient, agreement, promises, commitments, or details;
            keep suggestions and uncertainty as they are. Concise wording may
            remove repetition, not facts or requested actions.
            """
        case .custom:
            // The shared provider prompt supplies preservation rules without consuming this budget.
            return custom.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return goal + """


        Preserve facts, names, numbers, uncertainty, language, and the speaker's intention.
        Do not invent explanations, reasons, or commitments. Do not silently summarize
        away important details or omit distinct facts and requested actions.
        Generate only a proposal; leave the original and clipboard untouched until accepted.
        """
    }
}
