/// The top-level app state.
public enum AppState: Equatable {
    case idle
    case recording
}

/// Microphone permission status.
public enum MicPermission: Equatable {
    case notDetermined
    case authorized
    case denied
}

/// Successful result of a toggle operation.
public enum ToggleResult: Equatable {
    case startedRecording
    case stoppedRecording
}

/// Errors that can occur during a toggle operation.
public enum ToggleError: Error, Equatable {
    case permissionDenied
    case permissionNotDetermined
    case recordingFailed(String)
}

/// How the current recording was started, which determines what is allowed to stop it.
public enum RecordingMode: Equatable, Sendable {
    /// Push-to-talk: records while the shortcut is held, stops on release.
    case hold
    /// Press once to start, press the same shortcut again to stop.
    case toggle
}

/// Input events from the keyboard shortcuts (or the menu, which behaves like `toggle`).
public enum ShortcutEvent: Equatable, Sendable {
    case holdPressed
    case holdReleased
    case togglePressed
    /// Escape while recording — stop and throw the audio away.
    case cancel
    /// The hold key turned out not to be a push-to-talk press: it was only tapped, or used
    /// as a modifier for another key (Fn+Delete, Fn+←, …). Discards a *hold* recording
    /// only; a latched/toggle recording is unaffected.
    case holdInterrupted
}

/// What happened in response to a `ShortcutEvent`.
public enum ShortcutOutcome: Equatable {
    case started(RecordingMode)
    /// Recording stopped normally; the caller should run the transcription pipeline.
    case stopped
    /// Recording stopped and should be thrown away without transcribing.
    case discarded
    /// The toggle shortcut was pressed during a hold recording: it keeps running, now as a
    /// toggle recording, so releasing the hold key no longer stops it.
    case latched
    /// The event doesn't apply in the current state (e.g. key auto-repeat, or releasing
    /// the hold shortcut while a toggle recording is running).
    case ignored
    case failed(ToggleError)
}

/// Everything a finished run of the transcription pipeline produced, for delivery and for
/// the history/metrics store.
public struct PipelineResult: Equatable, Sendable {
    /// Exactly what the speech-to-text model returned.
    public let rawText: String
    /// What was delivered: the LLM's output, or `rawText` if formatting was off or failed.
    public let finalText: String
    /// Whether `finalText` actually came from the LLM.
    public let llmApplied: Bool
    public let transcriptionDuration: Duration
    /// The speech-to-text engine that produced `rawText`.
    public let transcriptionEngine: TranscriptionEngine
    /// Time spent in the formatter, including a failed or timed-out attempt. `nil` when no
    /// formatter is configured at all.
    public let formattingDuration: Duration?
    /// The model formatting was attempted with; nil if it wasn't attempted.
    public let formattingModel: FormattingModel?
    /// Tokens the formatting model reported (remote models only), even for a failed attempt.
    public let tokenUsage: TokenUsage?

    public init(
        rawText: String,
        finalText: String,
        llmApplied: Bool,
        transcriptionDuration: Duration,
        transcriptionEngine: TranscriptionEngine = .appleOnDevice,
        formattingDuration: Duration?,
        formattingModel: FormattingModel? = nil,
        tokenUsage: TokenUsage? = nil
    ) {
        self.rawText = rawText
        self.finalText = finalText
        self.llmApplied = llmApplied
        self.transcriptionDuration = transcriptionDuration
        self.transcriptionEngine = transcriptionEngine
        self.formattingDuration = formattingDuration
        self.formattingModel = formattingModel
        self.tokenUsage = tokenUsage
    }
}
