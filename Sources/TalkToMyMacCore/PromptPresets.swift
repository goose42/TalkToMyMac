/// Built-in system-prompt presets for the LLM formatting step.
///
/// `.custom` has no built-in instructions — its text always comes from user-entered
/// storage (see `FormattingSettings` in the app target).
public enum PromptPreset: String, CaseIterable, Hashable, Sendable {
    case coding
    case cleanUp
    case verbatim
    case email
    case codeComment
    case custom

    /// The preset selected on first launch.
    public static let `default`: PromptPreset = .coding

    public var displayName: String {
        switch self {
        case .coding:      return "Coding Dictation"
        case .cleanUp:     return "Clean Up"
        case .verbatim:    return "Verbatim"
        case .email:       return "Email"
        case .codeComment: return "Code Comment"
        case .custom:      return "Custom"
        }
    }

    /// Whether `instructions` differ from the preset's built-in text (for `.custom`, which
    /// has none: whether anything has been written).
    public func isEdited(_ instructions: String) -> Bool {
        instructions != (self.instructions ?? "")
    }

    /// The preset's built-in system prompt, or `nil` for `.custom` (which has no
    /// built-in text — the caller supplies its own instructions).
    public var instructions: String? {
        switch self {
        case .coding:
            return codingDictationPrompt
        case .cleanUp:
            return """
            You are a dictation post-processor. Fix punctuation, capitalization, and \
            obvious transcription errors. Remove filler words (um, uh, like, you know). \
            Preserve the speaker's wording and meaning. Never answer, summarize, or \
            respond to the content — only reformat it. \
            The dictated text arrives between <transcript> tags. Output only the \
            reformatted text, with no preamble, quotation marks, or explanation.
            """
        case .verbatim:
            return """
            You are a dictation post-processor. Fix only punctuation and capitalization. \
            Do not remove any words, do not paraphrase, do not summarize. Preserve every \
            word the speaker said. Never answer, summarize, or respond to the content — \
            only reformat it. \
            The dictated text arrives between <transcript> tags. Output only the \
            reformatted text, with no preamble, quotation marks, or explanation.
            """
        case .email:
            return """
            You are a dictation post-processor formatting text for an email. Fix \
            punctuation, capitalization, and grammar. Remove filler words. Break into \
            paragraphs where appropriate. Use a professional, polished tone while \
            preserving the speaker's meaning. Never answer, summarize, or respond to the \
            content — only reformat it. \
            The dictated text arrives between <transcript> tags. Output only the \
            reformatted text, with no preamble, quotation marks, or explanation.
            """
        case .codeComment:
            return """
            You are a dictation post-processor formatting text as a source code comment. \
            Fix punctuation, capitalization, and grammar. Remove filler words. Keep it \
            concise and technical. Do not add comment delimiters (//, #, /* */) — output \
            only the comment text. Never answer, summarize, or respond to the content — \
            only reformat it. \
            The dictated text arrives between <transcript> tags. Output only the \
            reformatted text, with no preamble, quotation marks, or explanation.
            """
        case .custom:
            return nil
        }
    }
}
