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
}
