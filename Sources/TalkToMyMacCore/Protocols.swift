/// Audio recording (start/stop microphone capture).
public protocol AudioRecording: AnyObject {
    func start() throws
    func stop() throws
    var isRecording: Bool { get }
}

/// Microphone permission checking and requesting.
public protocol PermissionChecking: AnyObject {
    func micPermission() -> MicPermission
    func requestMicPermission()
}

/// Visual recording indicator (e.g., status bar icon).
public protocol RecordingIndicator: AnyObject {
    func setRecording(_ recording: Bool)
    /// Called while a stopped recording is being transcribed/formatted, before delivery.
    /// Default implementation is a no-op so existing conformers aren't forced to add it.
    func setProcessing(_ processing: Bool)
}

public extension RecordingIndicator {
    func setProcessing(_ processing: Bool) {}
}

/// Speech-to-text engine.
public protocol SpeechTranscribing: AnyObject {
    var isReady: Bool { get }
    /// Transcribes raw mono float samples captured at `sampleRate`, reporting which engine
    /// ran. Nil if transcription failed or heard nothing.
    func transcribe(samples: [Float], sampleRate: Double) async -> TranscriptionOutcome?
    /// The engine's candidate transcriptions, best first. Empty if nothing was heard.
    func transcribeAlternatives(samples: [Float], sampleRate: Double) async -> [String]
}

public extension SpeechTranscribing {
    /// Engines without an n-best list offer just their single transcription.
    func transcribeAlternatives(samples: [Float], sampleRate: Double) async -> [String] {
        await transcribe(samples: samples, sampleRate: sampleRate).map { [$0.text] } ?? []
    }
}

/// Shifts pitch without changing tempo, for simulating a higher or lower voice. Returns nil
/// if the audio couldn't be rendered.
public protocol PitchShifting: AnyObject {
    func shift(_ samples: [Float], sampleRate: Double, cents: Int) -> [Float]?
}

/// Deterministic, model-free cleanup run between transcription and formatting.
public protocol TextCleaning: AnyObject {
    /// The cleaned-up transcript, or nil when cleanup is off and `text` should pass through.
    func clean(_ text: String) -> String?
}

/// Lets the user check the cleaned transcript before it's formatted and delivered, e.g. to
/// undo dictionary replacements before pasting into an app where they can't be fixed later.
public protocol TranscriptReviewing: AnyObject {
    /// The text to carry on with (`cleaned`, or the user's edit of it), or nil to deliver
    /// nothing. `raw` is the untouched transcript `cleaned` was made from.
    func review(raw: String, cleaned: String) async -> String?
}

/// Text post-processor / formatter (e.g., LLM cleanup).
public protocol TextFormatting: AnyObject {
    /// Whether a transcript of this many words should be formatted at all. When false, the
    /// pipeline delivers the raw transcript without calling `format(raw:)`.
    /// Default implementation always returns true.
    func shouldFormat(wordCount: Int) -> Bool
    /// Formats `raw`, reporting which model ran and what it cost. A nil `text` means the
    /// attempt failed and the raw transcript should be delivered.
    func format(raw: String) async -> FormattingOutcome
    /// Called when a recording starts, so the formatter can get ready (e.g. prewarm a model)
    /// while the user speaks. Default implementation is a no-op.
    func beginWarming()
    /// Called once the recording's transcript no longer needs formatting — after
    /// `format(raw:)`, or when it was skipped, discarded or nothing was heard. Default
    /// implementation is a no-op.
    func endWarming()
}

public extension TextFormatting {
    func shouldFormat(wordCount: Int) -> Bool { true }
    func beginWarming() {}
    func endWarming() {}
}

/// Output delivery (clipboard, text field injection, etc.).
public protocol OutputDelivering: AnyObject {
    func deliver(text: String) throws
}

/// Audio denoising pipeline.
public protocol AudioDenoising: AnyObject {
    func denoise(samples: [Float]) -> [Float]
}

/// Fills in a dictionary entry's fields (type, sound-alikes, context…) from just its written
/// form, e.g. with an on-device LLM. Returns nil if no suggestion could be produced.
public protocol DictionaryEntryGenerating: Sendable {
    func suggestEntry(for written: String) async -> DictionaryEntry?
}

/// Silences the Mac's own sound output for the length of a recording, so music or video
/// isn't playing over the dictation. Implementations decide whether muting is enabled and
/// must leave output exactly as they found it on restore (e.g. stay muted if the user had
/// already muted).
public protocol SystemAudioMuting: AnyObject {
    func muteForRecording()
    func restoreAfterRecording()
}
