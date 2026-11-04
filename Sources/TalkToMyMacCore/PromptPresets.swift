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

    /// The preset's Markdown file in `Sources/TalkToMyMacCore/Prompts`, without `.md`, or
    /// `nil` for `.custom`.
    public var fileName: String? {
        switch self {
        case .coding:      return "coding"
        case .cleanUp:     return "clean-up"
        case .verbatim:    return "verbatim"
        case .email:       return "email"
        case .codeComment: return "code-comment"
        case .custom:      return nil
        }
    }

    /// The preset's built-in system prompt, compiled from its Markdown file, or `nil` for
    /// `.custom` (which has no built-in text — the caller supplies its own instructions).
    public var instructions: String? {
        switch self {
        case .coding:      return PromptLibrary.coding
        case .cleanUp:     return PromptLibrary.cleanUp
        case .verbatim:    return PromptLibrary.verbatim
        case .email:       return PromptLibrary.email
        case .codeComment: return PromptLibrary.codeComment
        case .custom:      return nil
        }
    }
}
