import Foundation

/// Central controller — manages recording state and the transcription pipeline.
///
/// `@unchecked Sendable`: callers (e.g. a `@MainActor` app delegate) hold this across an
/// `await` boundary into `processRecording`, which runs on a concurrent executor rather
/// than being pinned to any actor. In practice there's a single call in flight at a time —
/// `toggle()` runs synchronously on the caller's thread and `processRecording` is awaited
/// sequentially per recording — so this widens the isolation checker's overly conservative
/// region-transfer analysis rather than papering over a real race.
public class RecorderController: @unchecked Sendable {
    public private(set) var state: AppState = .idle
    /// How the in-progress recording was started; `nil` when idle.
    public private(set) var activeMode: RecordingMode?

    private let recorder: AudioRecording
    private let permissionChecker: PermissionChecking
    private let indicator: RecordingIndicator
    private let transcriber: SpeechTranscribing?
    private let cleaner: TextCleaning?
    private let reviewer: TranscriptReviewing?
    private let formatter: TextFormatting?
    private let outputSink: OutputDelivering?
    private let denoiser: AudioDenoising?
    private let systemAudio: SystemAudioMuting?
    private let archiver: RecordingArchiving?

    public init(
        recorder: AudioRecording,
        permissionChecker: PermissionChecking,
        indicator: RecordingIndicator,
        transcriber: SpeechTranscribing? = nil,
        cleaner: TextCleaning? = nil,
        reviewer: TranscriptReviewing? = nil,
        formatter: TextFormatting? = nil,
        outputSink: OutputDelivering? = nil,
        denoiser: AudioDenoising? = nil,
        systemAudio: SystemAudioMuting? = nil,
        archiver: RecordingArchiving? = nil
    ) {
        self.recorder = recorder
        self.permissionChecker = permissionChecker
        self.indicator = indicator
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.reviewer = reviewer
        self.formatter = formatter
        self.outputSink = outputSink
        self.denoiser = denoiser
        self.systemAudio = systemAudio
        self.archiver = archiver
    }

    /// Toggle recording state. Returns success/failure.
    public func toggle() -> Result<ToggleResult, ToggleError> {
        switch state {
        case .idle:
            return start(mode: .toggle).map { .startedRecording }
        case .recording:
            return stop().map { .stoppedRecording }
        }
    }

    /// Routes a shortcut event through the hold/toggle state machine.
    ///
    /// Each mode can only be *ended* by its own shortcut, so brushing one shortcut while
    /// using the other never cuts a dictation short. Pressing toggle during a hold
    /// recording *latches* it into toggle mode instead of stopping it — which is also what
    /// makes Fn (hold) + Fn+Space (toggle) work, since Fn+Space begins with a hold press.
    public func handle(_ event: ShortcutEvent) -> ShortcutOutcome {
        switch (event, state) {
        case (.holdPressed, .idle):
            return outcome(of: start(mode: .hold), onSuccess: .started(.hold))
        case (.togglePressed, .idle):
            return outcome(of: start(mode: .toggle), onSuccess: .started(.toggle))

        case (.togglePressed, .recording) where activeMode == .hold:
            activeMode = .toggle
            return .latched

        case (.holdReleased, .recording) where activeMode == .hold,
             (.togglePressed, .recording) where activeMode == .toggle:
            return outcome(of: stop(), onSuccess: .stopped)

        case (.cancel, .recording),
             (.holdInterrupted, .recording) where activeMode == .hold:
            return outcome(of: stop(), onSuccess: .discarded)

        default:
            // Key auto-repeat, hold events during a toggle recording, or Esc when idle.
            return .ignored
        }
    }

    private func outcome(of result: Result<Void, ToggleError>, onSuccess: ShortcutOutcome) -> ShortcutOutcome {
        switch result {
        case .success:            return onSuccess
        case .failure(let error): return .failed(error)
        }
    }

    private func start(mode: RecordingMode) -> Result<Void, ToggleError> {
        switch permissionChecker.micPermission() {
        case .authorized:
            break
        case .notDetermined:
            permissionChecker.requestMicPermission()
            return .failure(.permissionNotDetermined)
        case .denied:
            return .failure(.permissionDenied)
        }

        do {
            try recorder.start()
        } catch {
            return .failure(.recordingFailed("\(error)"))
        }

        systemAudio?.muteForRecording()
        indicator.setRecording(true)
        state = .recording
        activeMode = mode
        return .success(())
    }

    private func stop() -> Result<Void, ToggleError> {
        do {
            try recorder.stop()
        } catch {
            return .failure(.recordingFailed("\(error)"))
        }

        systemAudio?.restoreAfterRecording()
        indicator.setRecording(false)
        state = .idle
        activeMode = nil
        return .success(())
    }

    /// Process recorded audio through the pipeline: denoise → transcribe → clean → review → format → deliver
    /// → archive. Returns the raw and final text plus step timings, or nil if any required step fails.
    @discardableResult
    public func processRecording(samples: [Float], sampleRate: Double) async -> PipelineResult? {
        // 6. Archive (optional) — the raw, un-denoised audio, kept whatever the outcome, and only
        //    once everything else is done so encoding can't delay the paste.
        let recordingID = UUID()
        defer { archiver?.archive(samples: samples, sampleRate: sampleRate, id: recordingID) }
        let clock = ContinuousClock()

        // 1. Denoise (optional)
        let processedSamples = denoiser?.denoise(samples: samples) ?? samples

        // 2. Transcribe (required)
        guard let transcriber = transcriber, transcriber.isReady else { return nil }
        indicator.setProcessing(true)
        defer { indicator.setProcessing(false) }

        let transcribeStart = clock.now
        guard let transcription = await transcriber.transcribe(samples: processedSamples, sampleRate: sampleRate) else { return nil }
        let rawText = transcription.text
        let transcriptionDuration = clock.now - transcribeStart

        // 3. Clean (optional — deterministic, no model). Cleaning a transcript down to
        //    nothing (e.g. just "um") counts as hearing nothing.
        var cleanedText = cleaner?.clean(rawText)
        if cleanedText?.isEmpty == true { return nil }
        var cleanText = cleanedText ?? rawText

        // 3b. Review (optional — the user may change the cleaned text, or cancel the paste;
        //     a cancelled transcript is still returned for history, just not formatted or delivered)
        var cancelled = false
        if let reviewer {
            if let reviewed = await reviewer.review(raw: rawText, cleaned: cleanText) {
                if reviewed != cleanText { cleanedText = reviewed }
                cleanText = reviewed
            } else {
                cancelled = true
            }
        }

        // 4. Format (optional — falls back to the cleaned text on any failure, and skipped
        //    entirely when the formatter declines a transcript this short)
        var outcome: FormattingOutcome?
        var formattingDuration: Duration?
        if !cancelled, let formatter, formatter.shouldFormat(wordCount: WordDiff.wordCount(cleanText)) {
            let formatStart = clock.now
            outcome = await formatter.format(raw: cleanText)
            formattingDuration = clock.now - formatStart
        }
        let formattedText = outcome?.text
        let finalText = formattedText ?? cleanText

        // 5. Deliver (optional — failure is non-fatal)
        if !cancelled, let sink = outputSink {
            try? sink.deliver(text: finalText)
        }

        return PipelineResult(
            rawText: rawText,
            cleanedText: cleanedText,
            finalText: finalText,
            llmApplied: formattedText != nil,
            transcriptionDuration: transcriptionDuration,
            transcriptionEngine: transcription.engine,
            formattingDuration: formattingDuration,
            formattingModel: outcome?.model,
            tokenUsage: outcome?.usage,
            recordingID: recordingID
        )
    }
}
