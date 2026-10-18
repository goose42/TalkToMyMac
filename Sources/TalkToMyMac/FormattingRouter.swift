import TalkToMyMacCore

/// The formatter the recording pipeline sees: skips formatting when it's off or the
/// transcript is under the short-dictation threshold, otherwise hands the transcript to
/// whichever model `settings.provider` selects. The provider is read on every call, so
/// switching it in Settings takes effect on the next dictation.
///
/// Every call is cut off after `FormattingDeadline.timeout`; past it, the transcript goes out
/// unformatted, as if formatting had been skipped, and the user is told through `notices`.
/// When a remote provider fails outright, the router also pauses it for an hour (see
/// `FormattingPause`); while paused, transcripts go out unformatted. A timeout alone
/// doesn't pause, since a slow response isn't a sign the next one will fail.
///
/// Warming is passed to the on-device model only, when it's the provider that will run.
/// `@unchecked Sendable`: holds only immutable references to thread-agnostic objects.
@available(macOS 26.0, *)
final class FormattingRouter: TextFormatting, @unchecked Sendable {
    private let settings: FormattingSettings
    private let onDevice: FoundationModelFormatter
    private let groq: GroqFormatter
    private let openRouter: OpenRouterFormatter
    private let notices: NoticePresenting?

    init(settings: FormattingSettings, onDevice: FoundationModelFormatter, groq: GroqFormatter,
         openRouter: OpenRouterFormatter, notices: NoticePresenting? = nil) {
        self.settings = settings
        self.onDevice = onDevice
        self.groq = groq
        self.openRouter = openRouter
        self.notices = notices
    }

    func shouldFormat(wordCount: Int) -> Bool {
        guard settings.isEnabled else { return false }
        if let pause = settings.activePause {
            print("[FormattingRouter] Skipping formatting: \(pause.provider.displayName) is paused "
                  + "until \(pause.until) after: \(pause.reason)")
            return false
        }
        guard settings.skipShortDictations, wordCount <= settings.formattingWordThreshold else { return true }
        print("[FormattingRouter] Skipping formatting: \(wordCount) word(s) "
              + "doesn't exceed the \(settings.formattingWordThreshold)-word threshold")
        return false
    }

    func beginWarming() {
        guard settings.isEnabled, settings.activePause == nil, settings.provider == .appleOnDevice else { return }
        onDevice.beginWarming()
    }

    func endWarming() {
        onDevice.endWarming()
    }

    func format(raw: String) async -> FormattingOutcome {
        let provider = settings.provider
        let formatter: any TextFormatting & Sendable
        let model: FormattingModel
        switch provider {
        case .appleOnDevice: (formatter, model) = (onDevice, .appleOnDevice)
        case .groq:          (formatter, model) = (groq, .groq(settings.groqModel))
        case .openRouter:    (formatter, model) = (openRouter, .openRouter(settings.openRouterModel))
        }

        let timeout = FormattingDeadline.timeout
        guard let outcome = await withDeadline(timeout, operation: { await formatter.format(raw: raw) }) else {
            print("[FormattingRouter] \(model.displayName) timed out after \(timeout)")
            notices?.present(.formattingTimedOut(provider))
            return FormattingOutcome(model: model, text: nil, failure: "Timed out after \(timeout)")
        }
        if let pause = FormattingPause.after(outcome) {
            settings.pauseFormatting(pause)
            notices?.present(.formattingFailed(pause))
        }
        return outcome
    }
}
