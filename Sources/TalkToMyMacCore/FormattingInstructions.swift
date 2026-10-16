import Foundation

/// Builds the user turn sent to the formatting model.
public enum FormattingInstructions {
    /// The user turn: just the raw transcript, tagged so the model treats it as text to edit.
    public static func userPrompt(transcript: String) -> String {
        "<transcript>\n\(transcript)\n</transcript>"
    }
}
