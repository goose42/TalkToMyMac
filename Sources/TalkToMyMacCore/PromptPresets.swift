/// Built-in system-prompt presets for the LLM formatting step.
///
/// `.custom` has no built-in instructions — its text always comes from user-entered
/// storage (see `FormattingSettings` in the app target).
public enum PromptPreset: String, CaseIterable, Hashable, Sendable {
    case cleanUp
    case verbatim
    case email
    case codeComment
    case custom

    public var displayName: String {
        switch self {
        case .cleanUp:     return "Clean Up"
        case .verbatim:    return "Verbatim"
        case .email:       return "Email"
        case .codeComment: return "Code Comment"
        case .custom:      return "Custom"
        }
    }

    /// The preset's built-in system prompt, or `nil` for `.custom` (which has no
    /// built-in text — the caller supplies its own instructions).
    public var instructions: String? {
        switch self {
        case .cleanUp:
            return """
            You are a dictation post-processor. Fix punctuation, capitalization, and \
            obvious transcription errors. Remove filler words (um, uh, like, you know). \
            Preserve the speaker's wording and meaning. Never answer, summarize, or \
            respond to the content — only reformat it.
            """
        case .verbatim:
            return """
            You are a dictation post-processor. Fix only punctuation and capitalization. \
            Do not remove any words, do not paraphrase, do not summarize. Preserve every \
            word the speaker said. Never answer, summarize, or respond to the content — \
            only reformat it.
            """
        case .email:
            return """
            You are a dictation post-processor formatting text for an email. Fix \
            punctuation, capitalization, and grammar. Remove filler words. Break into \
            paragraphs where appropriate. Use a professional, polished tone while \
            preserving the speaker's meaning. Never answer, summarize, or respond to the \
            content — only reformat it.
            """
        case .codeComment:
            return """
            You are a dictation post-processor formatting text as a source code comment. \
            Fix punctuation, capitalization, and grammar. Remove filler words. Keep it \
            concise and technical. Do not add comment delimiters (//, #, /* */) — output \
            only the comment text. Never answer, summarize, or respond to the content — \
            only reformat it.
            """
        case .custom:
            return nil
        }
    }
}
