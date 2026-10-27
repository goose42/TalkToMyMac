import AVFoundation
import CoreMedia
import OSLog
import Synchronization
import TalkToMyMacCore

/// Captures microphone audio into memory with an input-only `AVCaptureSession`. Nothing is
/// written while recording; finished dictations are saved afterwards by `RecordingArchiver`.
///
/// It deliberately isn't `AVAudioEngine`: an engine drives one audio unit for both input and
/// output, so starting it also opens the default *output* device. With a Bluetooth headset
/// as the output, that tied recording to the headset's clock and latency, which made the
/// waveform stutter and dropped words even when recording from the built-in microphone.
/// A capture session never touches the output.
///
/// `start()`/`stop()` are called from the Fn-key event tap on the main thread, and opening a
/// device can block, so they only flip `isRecording` and hand the work to `queue`. A failure
/// to start is reported through `onStartFailure`, and `finishedRecording()` waits for a stop
/// to complete.
///
/// `@unchecked Sendable`: session state is confined to `queue`; samples live behind a `Mutex`.
final class AudioCapture: AudioRecording, @unchecked Sendable {
    private let queue: AudioWorkQueue
    private var session: AVCaptureSession?
    private let sink = SampleSink()
    private let recordingFlag = Mutex(false)
    var isRecording: Bool { recordingFlag.withLock { $0 } }
    private let logger = Logger(subsystem: "com.talktomymac.dictate", category: "AudioCapture")
    private let sampleQueue = DispatchQueue(label: "com.talktomymac.audio.samples", qos: .userInteractive)

    /// Called on the audio queue when capture can't start after `start()` already returned.
    var onStartFailure: (@Sendable (Error) -> Void)?

    init(queue: AudioWorkQueue) {
        self.queue = queue
    }

    /// Which microphone to record from, read at the start of each recording.
    var inputDevice: () -> InputDeviceSelection = { .systemDefault }

    /// Whether to use only the built-in microphone, read at the start of each recording.
    var builtInOnly: () -> Bool = { false }

    /// Receives normalised (0…1) input levels while recording, roughly 30 per second, for
    /// the live waveform. Called on the audio thread — hop to the main queue before UI work.
    var onLevels: (@Sendable ([Float]) -> Void)?

    /// Root directory for all TalkToMyMac data.
    static var dataDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TalkToMyMac", isDirectory: true)
    }

    /// Subdirectory where audio recordings are saved.
    static var recordingsDirectory: URL {
        dataDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }

    /// File name of the recording saved for the dictation with `id` (its transcript's ID).
    static func recordingFileName(id: String) -> String {
        "recording-\(id).m4a"
    }

    /// The saved recording of the dictation with `id`, if it's on disk. WAVs are from older
    /// builds, matched to their transcripts by `scripts/link-recordings.sh`.
    static func recordingURL(id: String) -> URL? {
        let m4a = recordingsDirectory.appendingPathComponent(recordingFileName(id: id))
        let wav = m4a.deletingPathExtension().appendingPathExtension("wav")
        return [m4a, wav].first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Number and total size of the saved recordings.
    static func recordingsUsage() -> (count: Int, bytes: Int64) {
        recordingFiles().reduce((0, 0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return (total.0 + 1, total.1 + Int64(size))
        }
    }

    /// Deletes every saved recording. Returns how many files couldn't be removed.
    @discardableResult
    static func purgeRecordings() -> Int {
        recordingFiles().reduce(0) { failures, url in
            (try? FileManager.default.removeItem(at: url)) == nil ? failures + 1 : failures
        }
    }

    private static func recordingFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory, includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        )) ?? []
        // WAVs are from older builds, which wrote them live while recording.
        return files.filter { ["m4a", "wav"].contains($0.pathExtension.lowercased()) }
    }


    private struct CaptureError: LocalizedError {
        let errorDescription: String?
    }

    /// The microphone to record from: the built-in one, the chosen one, or the system default.
    private func captureDevice() -> AVCaptureDevice? {
        let selection = inputDevice()
        let builtInOnly = builtInOnly()
        let uid = InputRouting.targetUID(selection: selection, builtInOnly: builtInOnly,
                                         builtInUID: builtInOnly ? AudioDevices.builtInInputUID : nil,
                                         connected: { AudioDevices.cachedInputUIDs.value })
        if !builtInOnly, case .device(let chosen) = selection, uid == nil {
            logger.notice("Chosen microphone \(chosen, privacy: .public) isn't connected; using the system default")
        }
        if let uid, let device = AVCaptureDevice(uniqueID: uid) { return device }
        return AVCaptureDevice.default(for: .audio)
    }

    func start() throws {
        startRequestedAt.withLock { $0 = ProcessInfo.processInfo.systemUptime }
        recordingFlag.withLock { $0 = true }
        queue.async { [self] in
            do {
                try startCapture()
            } catch {
                recordingFlag.withLock { $0 = false }
                logger.error("Couldn't start recording: \(error.localizedDescription, privacy: .public)")
                onStartFailure?(error)
            }
        }
    }

    func stop() throws {
        recordingFlag.withLock { $0 = false }
        queue.async { [self] in stopCapture() }
    }

    /// Waits for any queued start/stop to finish, then returns the last recording's samples
    /// and sample rate, or nil if there isn't one.
    func finishedRecording() async -> (samples: [Float], sampleRate: Double)? {
        await queue.drain()
        return sink.finished()
    }

    private let startRequestedAt = Mutex<Double>(0)

    private func startCapture() throws {
        guard let device = captureDevice() else { throw CaptureError(errorDescription: "No microphone available") }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        // Mono float32 at the device's own sample rate.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CaptureError(errorDescription: "Couldn't set up the capture session")
        }
        session.addInput(input)
        session.addOutput(output)
        sink.reset(onLevels: onLevels)
        output.setSampleBufferDelegate(sink, queue: sampleQueue)
        session.startRunning()
        self.session = session
        let requested = startRequestedAt.withLock { $0 }
        logger.notice("Capture session running on \(device.localizedName, privacy: .public), \(Int((ProcessInfo.processInfo.systemUptime - requested) * 1000)) ms after key press")
    }

    private func stopCapture() {
        session?.stopRunning()
        session = nil
        // Let buffers already handed to the delegate finish before sealing the recording.
        sampleQueue.sync {}
        sink.seal()
    }

    /// Throws away the most recent (already stopped) recording. It was never written to
    /// disk, so dropping the in-memory samples leaves no trace.
    func discardLastRecording() {
        queue.async { [self] in sink.discard() }
    }

    /// Receives sample buffers on `sampleQueue`, accumulating channel-0 floats and reporting levels.
    private final class SampleSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
        private struct State {
            var samples: [Float] = []
            var sampleRate: Double = 0
            var finished: [Float]?
            var onLevels: (@Sendable ([Float]) -> Void)?
        }
        private let state = Mutex(State())

        func reset(onLevels: (@Sendable ([Float]) -> Void)?) {
            state.withLock { $0 = State(onLevels: onLevels) }
        }

        func seal() {
            state.withLock { $0.finished = $0.samples }
        }

        func discard() {
            state.withLock { $0.finished = nil }
        }

        func finished() -> (samples: [Float], sampleRate: Double)? {
            state.withLock { state in state.finished.map { ($0, state.sampleRate) } }
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr, !samples.isEmpty else { return }
            let chunk = max(Int(asbd.mSampleRate / 30), 1)
            let levels = AudioCapture.levels(of: samples, chunkSize: chunk)
            let onLevels = state.withLock { state -> (@Sendable ([Float]) -> Void)? in
                state.sampleRate = asbd.mSampleRate
                state.samples.append(contentsOf: samples)
                return state.onLevels
            }
            onLevels?(levels)
        }
    }

    /// RMS level of each `chunkSize` run of samples, mapped from -50…-10 dBFS onto 0…1
    /// (roughly silence to loud speech).
    fileprivate static func levels(of samples: [Float], chunkSize: Int) -> [Float] {
        stride(from: 0, to: samples.count, by: chunkSize).map { start in
            let chunk = samples[start..<min(start + chunkSize, samples.count)]
            let meanSquare = chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count)
            let db = 10 * log10(max(meanSquare, 1e-12))
            return min(max((db + 50) / 40, 0), 1)
        }
    }
}
