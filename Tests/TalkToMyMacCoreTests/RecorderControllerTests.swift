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
    var transcribeCallCount = 0
    var lastSamples: [Float]?
    var lastSampleRate: Double?

    init(isReady: Bool = true, result: String? = "hello world") {
        self.isReady = isReady
        self.transcribeResult = result
    }

    func transcribe(samples: [Float], sampleRate: Double) async -> String? {
        transcribeCallCount += 1
        lastSamples = samples
        lastSampleRate = sampleRate
        return transcribeResult
    }
}

final class MockFormatter: TextFormatting {
    var formatResult: String?
    var formatCallCount = 0
    var lastInput: String?

    init(result: String? = nil) {
        self.formatResult = result
    }

    func format(raw: String) async -> String? {
        formatCallCount += 1
        lastInput = raw
        return formatResult
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

// MARK: - Helpers

private func makeController(
    permission: MicPermission = .authorized,
    recorder: MockRecorder? = nil,
    indicator: MockIndicator? = nil,
    transcriber: MockTranscriber? = nil,
    formatter: MockFormatter? = nil,
    outputSink: MockOutputSink? = nil,
    denoiser: MockDenoiser? = nil
) -> (RecorderController, MockRecorder, MockPermissionChecker, MockIndicator) {
    let rec = recorder ?? MockRecorder()
    let perm = MockPermissionChecker(permission: permission)
    let ind = indicator ?? MockIndicator()
    let ctrl = RecorderController(
        recorder: rec,
        permissionChecker: perm,
        indicator: ind,
        transcriber: transcriber,
        formatter: formatter,
        outputSink: outputSink,
        denoiser: denoiser
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
        XCTAssertEqual(result, "hello world")
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
    // MARK: Pipeline — Formatter
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testProcessRecordingWithFormatterFormatsText() async {
        let transcriber = MockTranscriber(result: "hello world")
        let formatter = MockFormatter(result: "Hello, World!")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result, "Hello, World!")
        XCTAssertEqual(formatter.lastInput, "hello world")
    }

    func testProcessRecordingFormatterFailureUsesRawText() async {
        let transcriber = MockTranscriber(result: "hello world")
        let formatter = MockFormatter(result: nil)
        let (ctrl, _, _, _) = makeController(transcriber: transcriber, formatter: formatter)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result, "hello world")
    }

    func testProcessRecordingWithoutFormatterUsesRawText() async {
        let transcriber = MockTranscriber(result: "hello world")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result, "hello world")
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
        XCTAssertEqual(result, "hello world")
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
        XCTAssertEqual(result, "hello")
    }

    func testProcessRecordingWithoutOutputSinkStillReturnsText() async {
        let transcriber = MockTranscriber(result: "hello")
        let (ctrl, _, _, _) = makeController(transcriber: transcriber)
        let result = await ctrl.processRecording(samples: [1.0], sampleRate: 16000)
        XCTAssertEqual(result, "hello")
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
        // Return value is formatted text
        XCTAssertEqual(result, "Formatted Text")
    }
}
