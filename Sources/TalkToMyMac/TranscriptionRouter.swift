import TalkToMyMacCore

/// The transcriber the recording pipeline sees: hands each recording to the engine
/// `settings.transcriptionEngine` selects once that engine's model is loaded, and to Apple's
/// on-device model otherwise. The setting is read on every call, so switching engines in
/// Settings takes effect on the next dictation.
/// `@unchecked Sendable`: holds only immutable references to thread-agnostic objects.
@available(macOS 26.0, *)
final class TranscriptionRouter: SpeechTranscribing, @unchecked Sendable {
    private let settings: FormattingSettings
    private let apple: SpeechTranscriptionService
    private let parakeet: ParakeetTranscriptionService

    init(settings: FormattingSettings, apple: SpeechTranscriptionService, parakeet: ParakeetTranscriptionService) {
        self.settings = settings
        self.apple = apple
        self.parakeet = parakeet
    }

    var isReady: Bool { apple.isReady || engine == .parakeetTDTv3 }

    private var engine: TranscriptionEngine {
        TranscriptionEngine.resolve(selected: settings.transcriptionEngine, externalState: parakeet.state)
    }

    func transcribe(samples: [Float], sampleRate: Double) async -> TranscriptionOutcome? {
        switch engine {
        case .appleOnDevice:
            return await apple.transcribe(samples: samples, sampleRate: sampleRate)
        case .parakeetTDTv3:
            if let outcome = await parakeet.transcribe(samples: samples, sampleRate: sampleRate) {
                return outcome
            }
            // Don't lose the dictation: retry it with Apple's model.
            guard apple.isReady else { return nil }
            print("[TranscriptionRouter] Parakeet returned nothing; falling back to Apple's model")
            return await apple.transcribe(samples: samples, sampleRate: sampleRate)
        }
    }
}
