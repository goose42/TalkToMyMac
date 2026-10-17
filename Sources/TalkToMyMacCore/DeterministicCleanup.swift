/// Model-free transcript cleanup, ported from BetterWispr's post-processing pipeline. Runs
/// before (and independently of) LLM formatting.
public enum DeterministicCleanup {
    /// Drops fillers, self-repairs and stutters; on English text also applies voice commands,
    /// spoken numbers and email layout; finally swaps in the dictionary's written forms.
    /// Other languages are only trimmed and dictionary-corrected.
    public static func apply(_ text: String, dictionary: [DictionaryEntry]) -> String {
        let cleaned = TranscriptCleaner.clean(text, language: nil)
        var spoken = DictionaryReplacement.commands(dictionary, in: cleaned)
        if TranscriptCleaner.isEnglish(spoken, language: nil) {
            spoken = VoiceCommands.apply(spoken)
            spoken = EmailDictation.compose(spoken) ?? spoken
        }
        return DictionaryReplacement.apply(dictionary, to: spoken)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Swaps in the dictionary's written forms and nothing else, for when full cleanup is off.
    public static func applyDictionary(_ text: String, dictionary: [DictionaryEntry]) -> String {
        DictionaryReplacement.apply(dictionary, to: DictionaryReplacement.commands(dictionary, in: text))
    }

    /// Whether full cleanup runs on `text`. It's English-only for now: it runs when
    /// English is the chosen `language` (an ISO code), or when no language is chosen and `text`
    /// is detected as English or can't be detected. Otherwise only the dictionary is applied.
    public static func runs(on text: String, language: String?) -> Bool {
        TranscriptCleaner.isEnglishIgnoringFillers(text, language: language)
    }
}
