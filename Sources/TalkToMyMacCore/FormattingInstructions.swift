import Foundation

/// Builds the system prompt and user turn sent to the formatting model.
public enum FormattingInstructions {
    /// Marks where a prompt wants the dictionary JSON inserted.
    public static let dictionaryPlaceholder = "{{DICTIONARY}}"

    /// Inserts the dictionary into `base`. A prompt containing `{{DICTIONARY}}` gets the
    /// JSON there (`[]` when empty). A prompt without it gets the dictionary rules and JSON
    /// appended after a blank line, or is returned unchanged when the dictionary is empty.
    public static func compose(base: String, dictionary: [DictionaryEntry]) -> String {
        let json = DictionaryEntry.encode(dictionary)
        if base.contains(dictionaryPlaceholder) {
            return base.replacingOccurrences(of: dictionaryPlaceholder, with: json)
        }
        guard !dictionary.isEmpty else { return base }
        return base + "\n\n" + appendedDictionaryRules + "\n\n<dictionary>\n" + json + "\n</dictionary>"
    }

    /// The user turn: just the raw transcript, tagged so the model treats it as text to edit.
    public static func userPrompt(transcript: String) -> String {
        "<transcript>\n\(transcript)\n</transcript>"
    }

    /// A condensed version of the Coding Dictation preset's dictionary rules, for prompts
    /// that don't place the dictionary themselves.
    private static let appendedDictionaryRules = """
    <dictionary_rules>
    The user keeps a dictionary of terms they use often. Each entry has an exact "written" \
    form, a "type", optional "sounds_like" variants (common speech-to-text mis-hearings), and \
    optional "context". When a word or phrase in the transcript matches a "sounds_like" \
    variant or sounds like the term, AND the sentence fits the entry's type and context, \
    replace it with the exact "written" form. Do not substitute when the ordinary word \
    clearly fits better; if no entry clearly fits, leave the original word.
    </dictionary_rules>
    """
}
