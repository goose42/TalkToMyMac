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
    /// Transcribes raw mono float samples captured at `sampleRate`.
    func transcribe(samples: [Float], sampleRate: Double) async -> String?
}

/// Text post-processor / formatter (e.g., LLM cleanup).
public protocol TextFormatting: AnyObject {
    /// Whether a transcript of this many words should be formatted at all. When false, the
    /// pipeline delivers the raw transcript without calling `format(raw:)`.
    /// Default implementation always returns true.
    func shouldFormat(wordCount: Int) -> Bool
    func format(raw: String) async -> String?
}

public extension TextFormatting {
    func shouldFormat(wordCount: Int) -> Bool { true }
}

/// Output delivery (clipboard, text field injection, etc.).
public protocol OutputDelivering: AnyObject {
    func deliver(text: String) throws
}

/// Audio denoising pipeline.
public protocol AudioDenoising: AnyObject {
    func denoise(samples: [Float]) -> [Float]
}
