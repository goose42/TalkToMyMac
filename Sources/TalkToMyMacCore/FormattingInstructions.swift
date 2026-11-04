import Foundation

/// Builds the user turn sent to the formatting model.
public enum FormattingInstructions {
    /// How every user turn begins; the on-device formatter prewarms with it.
    public static let userPromptPrefix = "<transcript>\n"

    /// Sampling temperature for formatting. Low, so the model edits rather than rewrites.
    /// Shared by every formatter and the evals so they behave alike.
    public static let temperature = 0.2

    /// The longest formatted reply allowed, in tokens.
    public static let maximumResponseTokens = 2048

    /// The user turn: just the raw transcript, tagged so the model treats it as text to edit.
    public static func userPrompt(transcript: String) -> String {
        "\(userPromptPrefix)\(transcript)\n</transcript>"
    }
}
