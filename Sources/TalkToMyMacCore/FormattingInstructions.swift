import Foundation

/// Builds the user turn sent to the formatting model.
public enum FormattingInstructions {
    /// How every user turn begins; the on-device formatter prewarms with it.
    public static let userPromptPrefix = "<transcript>\n"

    /// The user turn: just the raw transcript, tagged so the model treats it as text to edit.
    public static func userPrompt(transcript: String) -> String {
        "\(userPromptPrefix)\(transcript)\n</transcript>"
    }
}
