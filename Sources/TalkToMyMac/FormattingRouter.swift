import TalkToMyMacCore

/// The formatter the recording pipeline sees: applies the short-dictation threshold, then
/// hands the transcript to whichever model `settings.provider` selects. The provider is read
/// on every call, so switching it in Settings takes effect on the next dictation.
/// `@unchecked Sendable`: holds only immutable references to thread-agnostic objects.
@available(macOS 26.0, *)
final class FormattingRouter: TextFormatting, @unchecked Sendable {
    private let settings: FormattingSettings
    private let onDevice: FoundationModelFormatter
    private let groq: GroqFormatter

    init(settings: FormattingSettings, onDevice: FoundationModelFormatter, groq: GroqFormatter) {
        self.settings = settings
        self.onDevice = onDevice
        self.groq = groq
    }

    func shouldFormat(wordCount: Int) -> Bool {
        guard settings.skipShortDictations, wordCount <= settings.formattingWordThreshold else { return true }
        print("[FormattingRouter] Skipping formatting: \(wordCount) word(s) "
              + "doesn't exceed the \(settings.formattingWordThreshold)-word threshold")
        return false
    }

    func format(raw: String) async -> String? {
        switch settings.provider {
        case .appleOnDevice: return await onDevice.format(raw: raw)
        case .groq:          return await groq.format(raw: raw)
        }
    }
}
