import TalkToMyMacCore

/// The cleaner the recording pipeline sees. The dictionary's written forms are always swapped
/// in here (the formatting model never sees the dictionary); full deterministic cleanup runs
/// too when it's on and the dictation is in English. The settings are read on every call, so
/// toggling cleanup, editing the dictionary or changing Parakeet's language takes effect on the
/// next dictation.
/// `@unchecked Sendable`: holds only an immutable reference to a thread-agnostic object.
final class CleanupRouter: TextCleaning, @unchecked Sendable {
    private let settings: FormattingSettings

    init(settings: FormattingSettings) {
        self.settings = settings
    }

    func clean(_ text: String) -> String? {
        let dictionary = settings.dictionaryEntries
        if settings.deterministicCleanupEnabled, DeterministicCleanup.runs(on: text, language: language) {
            return DeterministicCleanup.apply(text, dictionary: dictionary)
        }
        let replaced = DeterministicCleanup.applyDictionary(text, dictionary: dictionary)
        return replaced == text ? nil : replaced
    }

    /// The language the user chose for Parakeet, when Parakeet is the selected engine.
    private var language: String? {
        settings.transcriptionEngine == .parakeetTDTv3 ? settings.parakeetLanguage?.rawValue : nil
    }
}
