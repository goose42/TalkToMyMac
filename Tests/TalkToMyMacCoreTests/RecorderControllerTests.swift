import XCTest
@testable import TalkToMyMacCore

// MARK: - Mocks

final class MockRecorder: AudioRecording {
    var isRecording = false
    var startCallCount = 0
    var stopCallCount = 0
    var shouldFailStart = false
    var shouldFailStop = false

    func start() throws {
        if shouldFailStart {
            throw NSError(domain: "MockRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "mock start failure"])
        }
        isRecording = true
        startCallCount += 1
    }

    func stop() throws {
        if shouldFailStop {
            throw NSError(domain: "MockRecorder", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "mock stop failure"])
        }
        isRecording = false
        stopCallCount += 1
    }
}

final class MockPermissionChecker: PermissionChecking {
    var permission: MicPermission
    var requestCallCount = 0

    init(permission: MicPermission = .authorized) {
        self.permission = permission
    }

    func micPermission() -> MicPermission { permission }

    func requestMicPermission() {
        requestCallCount += 1
    }
}

final class MockIndicator: RecordingIndicator {
    var recording: Bool?
    var callCount = 0
    var processing: Bool?
    var processingCallCount = 0

    func setRecording(_ recording: Bool) {
        self.recording = recording
        callCount += 1
    }

    func setProcessing(_ processing: Bool) {
        self.processing = processing
        processingCallCount += 1
    }
}

final class MockTranscriber: SpeechTranscribing {
    var isReady: Bool
    var transcribeResult: String?
    var engine: TranscriptionEngine
    var transcribeCallCount = 0
    var lastSamples: [Float]?
    var lastSampleRate: Double?

    init(isReady: Bool = true, result: String? = "hello world", engine: TranscriptionEngine = .appleOnDevice) {
        self.isReady = isReady
        self.transcribeResult = result
        self.engine = engine
    }

    func transcribe(samples: [Float], sampleRate: Double) async -> TranscriptionOutcome? {
        transcribeCallCount += 1
        lastSamples = samples
        lastSampleRate = sampleRate
        return transcribeResult.map { TranscriptionOutcome(text: $0, engine: engine) }
    }
}

final class MockFormatter: TextFormatting {
    var formatResult: String?
    var model = FormattingModel.groq(.gptOss20b)
    var usage: TokenUsage?
    var formatCallCount = 0
    var lastInput: String?
    var shouldFormatResult = true
    var lastWordCount: Int?

    init(result: String? = nil) {
        self.formatResult = result
    }

    func shouldFormat(wordCount: Int) -> Bool {
        lastWordCount = wordCount
        return shouldFormatResult
    }

    func format(raw: String) async -> FormattingOutcome {
        formatCallCount += 1
        lastInput = raw
        return FormattingOutcome(model: model, text: formatResult, usage: usage)
    }
}

final class MockCleaner: TextCleaning {
    var cleanResult: String?
    var cleanCallCount = 0
    var lastInput: String?

    init(result: String?) {
        self.cleanResult = result
    }

    func clean(_ text: String) -> String? {
        cleanCallCount += 1
        lastInput = text
        return cleanResult
    }
}

final class MockReviewer: TranscriptReviewing {
    var reviewResult: String?
    var lastRaw: String?
    var lastCleaned: String?

    init(result: String?) {
        self.reviewResult = result
    }

    func review(raw: String, cleaned: String) async -> String? {
        lastRaw = raw
        lastCleaned = cleaned
        return reviewResult
    }
}

final class MockOutputSink: OutputDelivering {
    var deliverCallCount = 0
    var lastText: String?
    var shouldFail = false

    func deliver(text: String) throws {
        deliverCallCount += 1
        lastText = text
        if shouldFail {
            throw NSError(domain: "MockOutput", code: 1, userInfo: nil)
        }
    }
}

final class MockDenoiser: AudioDenoising {
    var denoiseCallCount = 0
    var lastSamples: [Float]?
    var denoiseResult: [Float]?

    init(result: [Float]? = nil) {
        self.denoiseResult = result
    }

    func denoise(samples: [Float]) -> [Float] {
        denoiseCallCount += 1
        lastSamples = samples
        return denoiseResult ?? samples
    }
}

final class MockSystemAudio: SystemAudioMuting {
    var muteCallCount = 0
    var restoreCallCount = 0

    func muteForRecording() { muteCallCount += 1 }
    func restoreAfterRecording() { restoreCallCount += 1 }
}

final class MockArchiver: RecordingArchiving {
    var archiveCallCount = 0
    var lastSamples: [Float]?
    var lastSampleRate: Double?
    var lastID: UUID?
    /// Runs inside `archive`, so a test can see what the pipeline had done by then.
    var onArchive: (() -> Void)?

    func archive(samples: [Float], sampleRate: Double, id: UUID) {
        archiveCallCount += 1
        lastID = id
        lastSamples = samples
        lastSampleRate = sampleRate
        onArchive?()
    }
}

// MARK: - Helpers

private func makeController(
    permission: MicPermission = .authorized,
    recorder: MockRecorder? = nil,
    indicator: MockIndicator? = nil,
    transcriber: MockTranscriber? = nil,
    cleaner: MockCleaner? = nil,
    reviewer: MockReviewer? = nil,
    formatter: MockFormatter? = nil,
    outputSink: MockOutputSink? = nil,
    denoiser: MockDenoiser? = nil,
    systemAudio: MockSystemAudio? = nil,
    archiver: MockArchiver? = nil
) -> (RecorderController, MockRecorder, MockPermissionChecker, MockIndicator) {
    let rec = recorder ?? MockRecorder()
    let perm = MockPermissionChecker(permission: permission)
    let ind = indicator ?? MockIndicator()
    let ctrl = RecorderController(
        recorder: rec,
        permissionChecker: perm,
        indicator: ind,
        transcriber: transcriber,
        cleaner: cleaner,
        reviewer: reviewer,
        formatter: formatter,
        outputSink: outputSink,
        denoiser: denoiser,
        systemAudio: systemAudio,
        archiver: archiver
    )
    return (ctrl, rec, perm, ind)
}

// MARK: - Tests

final class RecorderControllerTests: XCTestCase {

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: State Machine
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testStartsInIdleState() {
        let (ctrl, _, _, _) = makeController()
        XCTAssertEqual(ctrl.state, .idle)
    }

    func testToggleFromIdleStartsRecording() {
        let (ctrl, _, _, _) = makeController()
        let result = ctrl.toggle()
        XCTAssertEqual(result, .success(.startedRecording))
        XCTAssertEqual(ctrl.state, .recording)
    }

    func testToggleFromRecordingStopsRecording() {
        let (ctrl, _, _, _) = makeController()
        _ = ctrl.toggle() // start
        let result = ctrl.toggle() // stop
        XCTAssertEqual(result, .success(.stoppedRecording))
        XCTAssertEqual(ctrl.state, .idle)
    }

    func testFullCycleIdleRecordingIdle() {
        let (ctrl, _, _, _) = makeController()
        XCTAssertEqual(ctrl.state, .idle)

        _ = ctrl.toggle() // start
        XCTAssertEqual(ctrl.state, .recording)

        _ = ctrl.toggle() // stop
        XCTAssertEqual(ctrl.state, .idle)

        // Can start again
        _ = ctrl.toggle()
        XCTAssertEqual(ctrl.state, .recording)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: System audio muting
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testSystemAudioMutedWhenRecordingStarts() {
        let audio = MockSystemAudio()
        let (ctrl, _, _, _) = makeController(systemAudio: audio)
        _ = ctrl.toggle()
        XCTAssertEqual(audio.muteCallCount, 1)
        XCTAssertEqual(audio.restoreCallCount, 0)
    }

    func testSystemAudioRestoredWhenRecordingStops() {
        let audio = MockSystemAudio()
        let (ctrl, _, _, _) = makeController(systemAudio: audio)
        _ = ctrl.toggle() // start
        _ = ctrl.toggle() // stop
        XCTAssertEqual(audio.restoreCallCount, 1)
    }

    func testSystemAudioRestoredWhenRecordingDiscarded() {
        let audio = MockSystemAudio()
        let (ctrl, _, _, _) = makeController(systemAudio: audio)
        _ = ctrl.handle(.holdPressed)
        _ = ctrl.handle(.cancel)
        XCTAssertEqual(audio.restoreCallCount, 1)
    }

    func testSystemAudioNotMutedWhenPermissionDenied() {
        let audio = MockSystemAudio()
        let (ctrl, _, _, _) = makeController(permission: .denied, systemAudio: audio)
        _ = ctrl.toggle()
        XCTAssertEqual(audio.muteCallCount, 0)
    }

    func testSystemAudioNotMutedWhenRecorderFailsToStart() {
        let rec = MockRecorder()
        rec.shouldFailStart = true
        let audio = MockSystemAudio()
        let (ctrl, _, _, _) = makeController(recorder: rec, systemAudio: audio)
        _ = ctrl.toggle()
        XCTAssertEqual(audio.muteCallCount, 0)
    }

    func testLatchingDoesNotMuteAgain() {
        let audio = MockSystemAudio()
        let (ctrl, _, _, _) = makeController(systemAudio: audio)
        _ = ctrl.handle(.holdPressed)
        _ = ctrl.handle(.togglePressed) // latch
        _ = ctrl.handle(.holdReleased)  // ignored while latched
        XCTAssertEqual(audio.muteCallCount, 1)
        XCTAssertEqual(audio.restoreCallCount, 0)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Permissions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testToggleDeniedPermissionReturnsError() {
        let (ctrl, _, _, _) = makeController(permission: .denied)
        let result = ctrl.toggle()
        XCTAssertEqual(result, .failure(.permissionDenied))
    }

    func testToggleDeniedPermissionStaysIdle() {
        let (ctrl, _, _, _) = makeController(permission: .denied)
        _ = ctrl.toggle()
        XCTAssertEqual(ctrl.state, .idle)
    }

    func testToggleNotDeterminedTriggersRequest() {
        let (ctrl, _, perm, _) = makeController(permission: .notDetermined)
        _ = ctrl.toggle()
        XCTAssertEqual(perm.requestCallCount, 1)
    }

    func testToggleNotDeterminedReturnsError() {
        let (ctrl, _, _, _) = makeController(permission: .notDetermined)
        let result = ctrl.toggle()
        XCTAssertEqual(result, .failure(.permissionNotDetermined))
    }

    func testToggleNotDeterminedStaysIdle() {
        let (ctrl, _, _, _) = makeController(permission: .notDetermined)
        _ = ctrl.toggle()
        XCTAssertEqual(ctrl.state, .idle)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Indicator
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testIndicatorSetTrueWhenRecordingStarts() {
        let ind = MockIndicator()
        let (ctrl, _, _, _) = makeController(indicator: ind)
        _ = ctrl.toggle()
        XCTAssertEqual(ind.recording, true)
    }

    func testIndicatorSetFalseWhenRecordingStopped() {
        let ind = MockIndicator()
        let (ctrl, _, _, _) = makeController(indicator: ind)
        _ = ctrl.toggle() // start
        _ = ctrl.toggle() // stop
        XCTAssertEqual(ind.recording, false)
    }

    func testIndicatorNotChangedOnPermissionError() {
        let ind = MockIndicator()
        let (ctrl, _, _, _) = makeController(permission: .denied, indicator: ind)
        _ = ctrl.toggle()
        XCTAssertEqual(ind.callCount, 0)
    }

    func testIndicatorNotChangedOnRecorderStartFailure() {
        let rec = MockRecorder()
        rec.shouldFailStart = true
        let ind = MockIndicator()
        let (ctrl, _, _, _) = makeController(recorder: rec, indicator: ind)
        _ = ctrl.toggle()
        XCTAssertEqual(ind.callCount, 0)
    }

    func testIndicatorProcessingToggledDuringPipeline() async {
        let transcriber = MockTranscriber(result: "hello")
        let ind = MockIndicator()
        let (ctrl, _, _, _) = makeController(indicator: ind, transcriber: transcriber)
        _ = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        // Set to true then back to false around the transcribe/format/deliver steps.
        XCTAssertEqual(ind.processingCallCount, 2)
        XCTAssertEqual(ind.processing, false)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Recorder Interaction
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testRecorderStartCalledOnToggleFromIdle() {
        let (ctrl, rec, _, _) = makeController()
        _ = ctrl.toggle()
        XCTAssertEqual(rec.startCallCount, 1)
    }

    func testRecorderStopCalledOnToggleFromRecording() {
        let (ctrl, rec, _, _) = makeController()
        _ = ctrl.toggle() // start
        _ = ctrl.toggle() // stop
        XCTAssertEqual(rec.stopCallCount, 1)
    }

    func testRecorderStartFailureStaysIdle() {
        let rec = MockRecorder()
        rec.shouldFailStart = true
        let (ctrl, _, _, _) = makeController(recorder: rec)
        _ = ctrl.toggle()
        XCTAssertEqual(ctrl.state, .idle)
    }

    func testRecorderStartFailureReturnsError() {
        let rec = MockRecorder()
        rec.shouldFailStart = true
        let (ctrl, _, _, _) = makeController(recorder: rec)
        let result = ctrl.toggle()
        if case .failure(.recordingFailed) = result {
            // expected
        } else {
            XCTFail("Expected recordingFailed error, got \(result)")
        }
    }

    func testRecorderStopFailureStaysRecording() {
        let rec = MockRecorder()
        let (ctrl, _, _, _) = makeController(recorder: rec)
        _ = ctrl.toggle() // start
        rec.shouldFailStop = true
        let result = ctrl.toggle() // stop fails
        XCTAssertEqual(ctrl.state, .recording)
        if case .failure(.recordingFailed) = result {
            // expected
        } else {
            XCTFail("Expected recordingFailed error, got \(result)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Pipeline — Transcription
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testProcessRecordingTranscribesAudio() async {
        let transcriber = MockTranscriber(result: "hello")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        _ = await ctrl.processRecording(samples: [1.0, 2.0, 3.0], sampleRate: 16000)
        XCTAssertEqual(transcriber.transcribeCallCount, 1)
    }

    func testProcessRecordingPassesSampleRateToTranscriber() async {
        let transcriber = MockTranscriber(result: "hello")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        _ = await ctrl.processRecording(samples: [1.0, 2.0, 3.0], sampleRate: 48000)
        XCTAssertEqual(transcriber.lastSampleRate, 48000)
    }

    func testProcessRecordingReturnsTranscript() async {
        let transcriber = MockTranscriber(result: "hello world")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        let result = await ctrl.processRecording(samples: [1.0, 2.0], sampleRate: 16000)
        XCTAssertEqual(result?.finalText, "hello world")
    }

    func testProcessRecordingRecordsWhichEngineTranscribed() async {
        let transcriber = MockTranscriber(result: "hello world", engine: .parakeetTDTv3)
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        let result = await ctrl.processRecording(samples: [1.0, 2.0], sampleRate: 16000)
        XCTAssertEqual(result?.transcriptionEngine, .parakeetTDTv3)
    }

    func testProcessRecordingWithoutTranscriberReturnsNil() async {
        let (ctrl, _, _, _) = makeController()
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNil(result)
    }

    func testProcessRecordingWithTranscriberNotReadyReturnsNil() async {
        let transcriber = MockTranscriber(isReady: false)
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNil(result)
    }

    func testProcessRecordingTranscriptionFailureReturnsNil() async {
        let transcriber = MockTranscriber(result: nil)
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNil(result)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Pipeline — Denoiser
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testProcessRecordingWithDenoiserCallsDenoiser() async {
        let transcriber = MockTranscriber(result: "hello")
        let denoiser = MockDenoiser()
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, denoiser: denoiser)
        _ = await ctrl.processRecording(samples: [1.0, 2.0], sampleRate: 16000)
        XCTAssertEqual(denoiser.denoiseCallCount, 1)
    }

    func testProcessRecordingPassesDenoisedSamplesToTranscriber() async {
        let denoisedSamples: [Float] = [0.5, 0.6, 0.7]
        let transcriber = MockTranscriber(result: "hello")
        let denoiser = MockDenoiser(result: denoisedSamples)
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, denoiser: denoiser)
        _ = await ctrl.processRecording(samples: [1.0, 2.0, 3.0], sampleRate: 16000)
        XCTAssertEqual(transcriber.lastSamples, denoisedSamples)
    }

    func testProcessRecordingWithoutDenoiserPassesSamplesDirectly() async {
        let transcriber = MockTranscriber(result: "hello")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        let samples: [Float] = [1.0, 2.0, 3.0]
        _ = await ctrl.processRecording(samples: samples, sampleRate: 16000)
        XCTAssertEqual(transcriber.lastSamples, samples)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Pipeline — Cleaner
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testProcessRecordingCleanerReceivesRawTranscript() async {
        let transcriber = MockTranscriber(result: "um hello world")
        let cleaner = MockCleaner(result: "Hello world")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, cleaner: cleaner)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(cleaner.lastInput, "um hello world")
        XCTAssertEqual(result?.rawText, "um hello world")
        XCTAssertEqual(result?.cleanedText, "Hello world")
    }

    func testProcessRecordingFormatsCleanedText() async {
        let transcriber = MockTranscriber(result: "um hello world")
        let cleaner = MockCleaner(result: "Hello world")
        let formatter = MockFormatter(result: "Hello, world.")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, cleaner: cleaner, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(formatter.lastInput, "Hello world")
        XCTAssertEqual(result?.finalText, "Hello, world.")
    }

    func testProcessRecordingCountsCleanedWordsForShouldFormat() async {
        let transcriber = MockTranscriber(result: "um uh hello there world")
        let cleaner = MockCleaner(result: "hello there world")
        let formatter = MockFormatter(result: "Hello there, world.")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, cleaner: cleaner, formatter: formatter)
        _ = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(formatter.lastWordCount, 3)
    }

    func testProcessRecordingDeliversCleanedTextWithoutFormatter() async {
        let transcriber = MockTranscriber(result: "um hello world")
        let cleaner = MockCleaner(result: "Hello world")
        let sink = MockOutputSink()
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, cleaner: cleaner, outputSink: sink)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.finalText, "Hello world")
        XCTAssertEqual(result?.llmApplied, false)
        XCTAssertEqual(sink.lastText, "Hello world")
    }

    func testProcessRecordingFormatterFailureFallsBackToCleanedText() async {
        let transcriber = MockTranscriber(result: "um hello world")
        let cleaner = MockCleaner(result: "Hello world")
        let formatter = MockFormatter(result: nil)
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, cleaner: cleaner, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.finalText, "Hello world")
    }

    func testProcessRecordingCleanerOffLeavesCleanedTextNil() async {
        let transcriber = MockTranscriber(result: "um hello world")
        let cleaner = MockCleaner(result: nil)
        let formatter = MockFormatter(result: nil)
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, cleaner: cleaner, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNil(result?.cleanedText)
        XCTAssertEqual(formatter.lastInput, "um hello world")
        XCTAssertEqual(result?.finalText, "um hello world")
    }

    func testProcessRecordingWithoutCleanerLeavesCleanedTextNil() async {
        let transcriber = MockTranscriber(result: "hello world")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNil(result?.cleanedText)
    }

    /// "um" on its own cleans to nothing — treat it like the transcriber hearing nothing.
    func testProcessRecordingEmptyCleanedTextDeliversNothing() async {
        let transcriber = MockTranscriber(result: "um")
        let cleaner = MockCleaner(result: "")
        let formatter = MockFormatter(result: "Um.")
        let sink = MockOutputSink()
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, cleaner: cleaner, formatter: formatter, outputSink: sink)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNil(result)
        XCTAssertEqual(formatter.formatCallCount, 0)
        XCTAssertEqual(sink.deliverCallCount, 0)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Pipeline — Reviewer
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testReviewedTextIsFormattedAndDelivered() async {
        let transcriber = MockTranscriber(result: "use the rest API")
        let cleaner = MockCleaner(result: "use the REST API")
        let reviewer = MockReviewer(result: "use the rest API!")
        let formatter = MockFormatter(result: nil)
        let sink = MockOutputSink()
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, cleaner: cleaner, reviewer: reviewer,
                                             formatter: formatter, outputSink: sink)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(reviewer.lastRaw, "use the rest API")
        XCTAssertEqual(reviewer.lastCleaned, "use the REST API")
        XCTAssertEqual(formatter.lastInput, "use the rest API!")
        XCTAssertEqual(result?.cleanedText, "use the rest API!")
        XCTAssertEqual(sink.lastText, "use the rest API!")
    }

    func testReviewerSeesRawTextWhenCleanupIsOff() async {
        let transcriber = MockTranscriber(result: "hello world")
        let reviewer = MockReviewer(result: "hello world")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, reviewer: reviewer)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(reviewer.lastCleaned, "hello world")
        XCTAssertNil(result?.cleanedText)
    }

    /// A cancelled review still keeps the transcript for history; it just isn't formatted or pasted.
    func testCancelledReviewSkipsFormattingAndDelivery() async {
        let transcriber = MockTranscriber(result: "use the rest API")
        let cleaner = MockCleaner(result: "use the REST API")
        let reviewer = MockReviewer(result: nil)
        let formatter = MockFormatter(result: "Use the REST API.")
        let sink = MockOutputSink()
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, cleaner: cleaner, reviewer: reviewer,
                                             formatter: formatter, outputSink: sink)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(formatter.formatCallCount, 0)
        XCTAssertEqual(sink.deliverCallCount, 0)
        XCTAssertEqual(result?.finalText, "use the REST API")
        XCTAssertEqual(result?.llmApplied, false)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Pipeline — Formatter
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testProcessRecordingWithFormatterFormatsText() async {
        let transcriber = MockTranscriber(result: "hello world")
        let formatter = MockFormatter(result: "Hello, World!")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.finalText, "Hello, World!")
        XCTAssertEqual(formatter.lastInput, "hello world")
    }

    func testProcessRecordingFormatterFailureUsesRawText() async {
        let transcriber = MockTranscriber(result: "hello world")
        let formatter = MockFormatter(result: nil)
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.finalText, "hello world")
    }

    func testProcessRecordingFormatterFailureReportsLLMNotApplied() async {
        let transcriber = MockTranscriber(result: "hello world")
        let formatter = MockFormatter(result: nil)
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.rawText, "hello world")
        XCTAssertEqual(result?.llmApplied, false)
        // The attempt was still timed, so slow failures (e.g. timeouts) show up in metrics.
        XCTAssertNotNil(result?.formattingDuration)
    }

    func testProcessRecordingReportsFormatterModelAndUsage() async {
        let transcriber = MockTranscriber(result: "hello world")
        let formatter = MockFormatter(result: "Hello, world.")
        formatter.usage = TokenUsage(input: 120, output: 30, reasoning: 12, cached: 0)
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.formattingModel, .groq(.gptOss20b))
        XCTAssertEqual(result?.tokenUsage, TokenUsage(input: 120, output: 30, reasoning: 12, cached: 0))
    }

    func testProcessRecordingFailedAttemptStillReportsModelAndUsage() async {
        // A remote call can be billed even when its output is unusable.
        let transcriber = MockTranscriber(result: "hello world")
        let formatter = MockFormatter(result: nil)
        formatter.usage = TokenUsage(input: 120, output: 2048, reasoning: 2048, cached: 0)
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.llmApplied, false)
        XCTAssertEqual(result?.formattingModel, .groq(.gptOss20b))
        XCTAssertEqual(result?.tokenUsage?.output, 2048)
    }

    func testProcessRecordingSkippedFormatterHasNoModel() async {
        let transcriber = MockTranscriber(result: "no")
        let formatter = MockFormatter(result: "No.")
        formatter.shouldFormatResult = false
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNil(result?.formattingModel)
        XCTAssertNil(result?.tokenUsage)
    }

    func testProcessRecordingWithoutFormatterHasNoFormattingDuration() async {
        let transcriber = MockTranscriber(result: "hello world")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.llmApplied, false)
        XCTAssertNil(result?.formattingDuration)
    }

    func testProcessRecordingWithoutFormatterUsesRawText() async {
        let transcriber = MockTranscriber(result: "hello world")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.finalText, "hello world")
    }

    func testProcessRecordingSkipsFormatterWhenShouldFormatIsFalse() async {
        let transcriber = MockTranscriber(result: "no")
        let formatter = MockFormatter(result: "No.")
        formatter.shouldFormatResult = false
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.finalText, "no")
        XCTAssertEqual(result?.llmApplied, false)
        XCTAssertNil(result?.formattingDuration)
        XCTAssertEqual(formatter.formatCallCount, 0)
    }

    func testProcessRecordingPassesTranscriptWordCountToShouldFormat() async {
        let transcriber = MockTranscriber(result: "  move that  to the\nleft ")
        let formatter = MockFormatter(result: "Move that to the left.")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, formatter: formatter)
        _ = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(formatter.lastWordCount, 5)
    }

    /// The single most important fallback: if the LLM is unavailable/fails, the raw
    /// transcript must still reach the output sink — dictation should never go silent
    /// just because on-device formatting couldn't run.
    func testProcessRecordingFormatterNilStillDeliversRawTextToSink() async {
        let transcriber = MockTranscriber(result: "hello world")
        let formatter = MockFormatter(result: nil)
        let sink = MockOutputSink()
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, formatter: formatter, outputSink: sink)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.finalText, "hello world")
        XCTAssertEqual(sink.deliverCallCount, 1)
        XCTAssertEqual(sink.lastText, "hello world")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Pipeline — Output Sink
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testProcessRecordingDeliversToOutputSink() async {
        let transcriber = MockTranscriber(result: "hello")
        let sink = MockOutputSink()
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, outputSink: sink)
        _ = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(sink.deliverCallCount, 1)
        XCTAssertEqual(sink.lastText, "hello")
    }

    func testProcessRecordingOutputSinkFailureStillReturnsText() async {
        let transcriber = MockTranscriber(result: "hello")
        let sink = MockOutputSink()
        sink.shouldFail = true
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, outputSink: sink)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.finalText, "hello")
    }

    func testProcessRecordingWithoutOutputSinkStillReturnsText() async {
        let transcriber = MockTranscriber(result: "hello")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result?.finalText, "hello")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Shortcut state machine — hold (push to talk)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testHoldPressStartsHoldRecording() {
        let (ctrl, rec, _, _) = makeController()
        XCTAssertEqual(ctrl.handle(.holdPressed), .started(.hold))
        XCTAssertEqual(ctrl.state, .recording)
        XCTAssertEqual(ctrl.activeMode, .hold)
        XCTAssertEqual(rec.startCallCount, 1)
    }

    func testHoldReleaseStopsHoldRecording() {
        let (ctrl, rec, _, _) = makeController()
        _ = ctrl.handle(.holdPressed)
        XCTAssertEqual(ctrl.handle(.holdReleased), .stopped)
        XCTAssertEqual(ctrl.state, .idle)
        XCTAssertNil(ctrl.activeMode)
        XCTAssertEqual(rec.stopCallCount, 1)
    }

    /// Carbon may re-deliver the press while the key is held; that must not restart.
    func testHoldPressWhileHoldRecordingIsIgnored() {
        let (ctrl, rec, _, _) = makeController()
        _ = ctrl.handle(.holdPressed)
        XCTAssertEqual(ctrl.handle(.holdPressed), .ignored)
        XCTAssertEqual(rec.startCallCount, 1)
    }

    func testHoldReleaseWhenIdleIsIgnored() {
        let (ctrl, rec, _, _) = makeController()
        XCTAssertEqual(ctrl.handle(.holdReleased), .ignored)
        XCTAssertEqual(rec.stopCallCount, 0)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Shortcut state machine — toggle
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testTogglePressStartsThenStops() {
        let (ctrl, _, _, _) = makeController()
        XCTAssertEqual(ctrl.handle(.togglePressed), .started(.toggle))
        XCTAssertEqual(ctrl.activeMode, .toggle)
        XCTAssertEqual(ctrl.handle(.togglePressed), .stopped)
        XCTAssertEqual(ctrl.state, .idle)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Shortcut state machine — cross-mode isolation
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testHoldReleaseDoesNotStopToggleRecording() {
        let (ctrl, _, _, _) = makeController()
        _ = ctrl.handle(.togglePressed)
        XCTAssertEqual(ctrl.handle(.holdReleased), .ignored)
        XCTAssertEqual(ctrl.state, .recording)
        XCTAssertEqual(ctrl.activeMode, .toggle)
    }

    func testHoldPressDoesNotAffectToggleRecording() {
        let (ctrl, rec, _, _) = makeController()
        _ = ctrl.handle(.togglePressed)
        XCTAssertEqual(ctrl.handle(.holdPressed), .ignored)
        XCTAssertEqual(ctrl.activeMode, .toggle)
        XCTAssertEqual(rec.startCallCount, 1)
    }

    /// Toggle during a hold latches it (Fn held → Space): keeps recording, no restart.
    func testTogglePressDuringHoldLatchesIntoToggle() {
        let (ctrl, rec, _, _) = makeController()
        _ = ctrl.handle(.holdPressed)
        XCTAssertEqual(ctrl.handle(.togglePressed), .latched)
        XCTAssertEqual(ctrl.state, .recording)
        XCTAssertEqual(ctrl.activeMode, .toggle)
        XCTAssertEqual(rec.startCallCount, 1)
        XCTAssertEqual(rec.stopCallCount, 0)
    }

    /// Full Fn / Fn+Space flow: Fn down, Space (latch), Fn up (ignored), then Fn down again
    /// (ignored), Space (stop), Fn up (ignored).
    func testLatchedRecordingSurvivesHoldReleaseAndStopsOnToggle() {
        let (ctrl, rec, _, _) = makeController()
        XCTAssertEqual(ctrl.handle(.holdPressed), .started(.hold))
        XCTAssertEqual(ctrl.handle(.togglePressed), .latched)
        XCTAssertEqual(ctrl.handle(.holdInterrupted), .ignored) // Fn released after combo
        XCTAssertEqual(ctrl.state, .recording)
        XCTAssertEqual(ctrl.handle(.holdPressed), .ignored)
        XCTAssertEqual(ctrl.handle(.togglePressed), .stopped)
        XCTAssertEqual(ctrl.handle(.holdInterrupted), .ignored)
        XCTAssertEqual(ctrl.state, .idle)
        XCTAssertEqual(rec.startCallCount, 1)
        XCTAssertEqual(rec.stopCallCount, 1)
    }

    /// Fn tapped briefly, or used as a modifier (Fn+Delete): discard, don't transcribe.
    func testHoldInterruptedDiscardsHoldRecording() {
        let (ctrl, _, _, _) = makeController()
        _ = ctrl.handle(.holdPressed)
        XCTAssertEqual(ctrl.handle(.holdInterrupted), .discarded)
        XCTAssertEqual(ctrl.state, .idle)
    }

    func testHoldInterruptedDoesNotAffectToggleRecording() {
        let (ctrl, _, _, _) = makeController()
        _ = ctrl.handle(.togglePressed)
        XCTAssertEqual(ctrl.handle(.holdInterrupted), .ignored)
        XCTAssertEqual(ctrl.state, .recording)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Shortcut state machine — cancel (Esc)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testCancelDiscardsToggleRecording() {
        let (ctrl, rec, _, ind) = makeController()
        _ = ctrl.handle(.togglePressed)
        XCTAssertEqual(ctrl.handle(.cancel), .discarded)
        XCTAssertEqual(ctrl.state, .idle)
        XCTAssertNil(ctrl.activeMode)
        XCTAssertEqual(rec.stopCallCount, 1)
        XCTAssertEqual(ind.recording, false)
    }

    func testCancelDiscardsHoldRecordingAndLaterReleaseIsIgnored() {
        let (ctrl, _, _, _) = makeController()
        _ = ctrl.handle(.holdPressed)
        XCTAssertEqual(ctrl.handle(.cancel), .discarded)
        XCTAssertEqual(ctrl.handle(.holdReleased), .ignored)
        XCTAssertEqual(ctrl.state, .idle)
    }

    func testCancelWhenIdleIsIgnored() {
        let (ctrl, rec, _, _) = makeController()
        XCTAssertEqual(ctrl.handle(.cancel), .ignored)
        XCTAssertEqual(rec.stopCallCount, 0)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Shortcut state machine — failures
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testHoldPressWithDeniedPermissionFailsAndStaysIdle() {
        let (ctrl, _, _, _) = makeController(permission: .denied)
        XCTAssertEqual(ctrl.handle(.holdPressed), .failed(.permissionDenied))
        XCTAssertEqual(ctrl.state, .idle)
        XCTAssertNil(ctrl.activeMode)
    }

    func testStopFailureKeepsModeSoItCanBeRetried() {
        let rec = MockRecorder()
        let (ctrl, _, _, _) = makeController(recorder: rec)
        _ = ctrl.handle(.holdPressed)
        rec.shouldFailStop = true
        if case .failed(.recordingFailed) = ctrl.handle(.holdReleased) {} else {
            XCTFail("expected recordingFailed")
        }
        XCTAssertEqual(ctrl.state, .recording)
        XCTAssertEqual(ctrl.activeMode, .hold)
    }

    /// The menu's toggle() and the shortcut state machine share state.
    func testLegacyToggleSetsToggleMode() {
        let (ctrl, _, _, _) = makeController()
        _ = ctrl.toggle()
        XCTAssertEqual(ctrl.activeMode, .toggle)
        XCTAssertEqual(ctrl.handle(.togglePressed), .stopped)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Full Pipeline Integration
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testProcessRecordingFullPipeline() async {
        let denoisedSamples: [Float] = [0.1, 0.2]
        let transcriber = MockTranscriber(result: "raw text")
        let formatter = MockFormatter(result: "Formatted Text")
        let sink = MockOutputSink()
        let denoiser = MockDenoiser(result: denoisedSamples)

        let (ctrl, _, _, _) = makeController(
            transcriber: transcriber,
            formatter: formatter,
            outputSink: sink,
            denoiser: denoiser
        )

        let result = await ctrl.processRecording(samples: [1.0, 2.0, 3.0], sampleRate: 16000)

        // Denoiser was called with original samples
        XCTAssertEqual(denoiser.lastSamples, [1.0, 2.0, 3.0])
        // Transcriber received denoised samples
        XCTAssertEqual(transcriber.lastSamples, denoisedSamples)
        // Formatter received raw transcript
        XCTAssertEqual(formatter.lastInput, "raw text")
        // Output sink received formatted text
        XCTAssertEqual(sink.lastText, "Formatted Text")
        // Return value carries both the raw and the formatted text
        XCTAssertEqual(result?.rawText, "raw text")
        XCTAssertEqual(result?.finalText, "Formatted Text")
        XCTAssertEqual(result?.llmApplied, true)
        XCTAssertNotNil(result?.formattingDuration)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: Pipeline — Archiving
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testProcessRecordingArchivesRawSamplesNotDenoised() async {
        let archiver = MockArchiver()
        let (ctrl, _, _, _) = makeController(transcriber: MockTranscriber(),
                                             denoiser: MockDenoiser(result: [0.5]), archiver: archiver)
        _ = await ctrl.processRecording(samples: [1.0, 2.0, 3.0], sampleRate: 48000)
        XCTAssertEqual(archiver.archiveCallCount, 1)
        XCTAssertEqual(archiver.lastSamples, [1.0, 2.0, 3.0])
        XCTAssertEqual(archiver.lastSampleRate, 48000)
    }

    func testProcessRecordingArchivesAfterDelivery() async {
        let sink = MockOutputSink()
        let archiver = MockArchiver()
        var deliveriesBeforeArchive: Int?
        archiver.onArchive = { deliveriesBeforeArchive = sink.deliverCallCount }
        let (ctrl, _, _, _) = makeController(transcriber: MockTranscriber(), outputSink: sink, archiver: archiver)
        _ = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(deliveriesBeforeArchive, 1)
    }

    func testProcessRecordingArchivesWhenTranscriberNotReady() async {
        let archiver = MockArchiver()
        let (ctrl, _, _, _) = makeController(transcriber: MockTranscriber(isReady: false), archiver: archiver)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNil(result)
        XCTAssertEqual(archiver.archiveCallCount, 1)
    }

    func testProcessRecordingArchivesWhenNothingWasHeard() async {
        let archiver = MockArchiver()
        let (ctrl, _, _, _) = makeController(transcriber: MockTranscriber(result: nil), archiver: archiver)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNil(result)
        XCTAssertEqual(archiver.archiveCallCount, 1)
    }

    func testProcessRecordingArchivesWhenCleanedToNothing() async {
        let archiver = MockArchiver()
        let (ctrl, _, _, _) = makeController(transcriber: MockTranscriber(result: "um"),
                                             cleaner: MockCleaner(result: ""), archiver: archiver)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNil(result)
        XCTAssertEqual(archiver.archiveCallCount, 1)
    }

    func testProcessRecordingArchivesWhenReviewCancels() async {
        let sink = MockOutputSink()
        let archiver = MockArchiver()
        let (ctrl, _, _, _) = makeController(transcriber: MockTranscriber(), reviewer: MockReviewer(result: nil),
                                             outputSink: sink, archiver: archiver)
        _ = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(sink.deliverCallCount, 0)
        XCTAssertEqual(archiver.archiveCallCount, 1)
    }

    func testProcessRecordingArchivesOncePerRecording() async {
        let archiver = MockArchiver()
        let (ctrl, _, _, _) = makeController(transcriber: MockTranscriber(), archiver: archiver)
        _ = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        _ = await ctrl.processRecording(samples: [2.0], sampleRate: 16000)
        XCTAssertEqual(archiver.archiveCallCount, 2)
        XCTAssertEqual(archiver.lastSamples, [2.0])
    }

    func testProcessRecordingArchivesUnderTheResultsRecordingID() async {
        let archiver = MockArchiver()
        let (ctrl, _, _, _) = makeController(transcriber: MockTranscriber(), archiver: archiver)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNotNil(result?.recordingID)
        XCTAssertEqual(archiver.lastID, result?.recordingID)
    }

    func testProcessRecordingUsesANewRecordingIDEachTime() async {
        let archiver = MockArchiver()
        let (ctrl, _, _, _) = makeController(transcriber: MockTranscriber(), archiver: archiver)
        let first = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        let second = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNotEqual(first?.recordingID, second?.recordingID)
    }

    func testProcessRecordingArchivesWithAnIDEvenWithoutAResult() async {
        let archiver = MockArchiver()
        let (ctrl, _, _, _) = makeController(transcriber: MockTranscriber(result: nil), archiver: archiver)
        _ = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertNotNil(archiver.lastID)
    }
}
