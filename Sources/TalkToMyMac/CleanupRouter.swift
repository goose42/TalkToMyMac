import TalkToMyMacCore

/// The cleaner the recording pipeline sees. The dictionary's written forms are always swapped
/// in here (the formatting model never sees the dictionary); full deterministic cleanup runs
/// too when it's on. The settings are read on every call, so toggling cleanup or editing the
/// dictionary takes effect on the next dictation.
/// `@unchecked Sendable`: holds only an immutable reference to a thread-agnostic object.
final class CleanupRouter: TextCleaning, @unchecked Sendable {
    private let settings: FormattingSettings

    init(settings: FormattingSettings) {
        self.settings = settings
    }

    func clean(_ text: String) -> String? {
        let dictionary = settings.dictionaryEntries
        if settings.deterministicCleanupEnabled {
            return DeterministicCleanup.apply(text, dictionary: dictionary)
        }
        let replaced = DeterministicCleanup.applyDictionary(text, dictionary: dictionary)
        return replaced == text ? nil : replaced
    }
}
