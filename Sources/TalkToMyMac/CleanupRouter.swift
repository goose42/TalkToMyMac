import TalkToMyMacCore

/// The cleaner the recording pipeline sees: passes transcripts through untouched when
/// deterministic cleanup is off, otherwise cleans them against the current dictionary. The
/// settings are read on every call, so toggling cleanup or editing the dictionary takes effect
/// on the next dictation.
/// `@unchecked Sendable`: holds only an immutable reference to a thread-agnostic object.
final class CleanupRouter: TextCleaning, @unchecked Sendable {
    private let settings: FormattingSettings

    init(settings: FormattingSettings) {
        self.settings = settings
    }

    func clean(_ text: String) -> String? {
        guard settings.deterministicCleanupEnabled else { return nil }
        return DeterministicCleanup.apply(text, dictionary: settings.dictionaryEntries)
    }
}
