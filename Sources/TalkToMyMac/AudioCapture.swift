import AVFoundation
import TalkToMyMacCore

/// Captures microphone audio via AVAudioEngine and writes to a WAV file in the cache directory.
/// Also keeps the raw PCM samples in memory so callers can skip re-reading from disk.
final class AudioCapture: AudioRecording {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private(set) var isRecording = false
    private(set) var lastRecordingPath: String?

    /// In-memory accumulation of raw Float32 samples (channel 0) captured during recording.
    private(set) var lastRecordingRawSamples: [Float]?
    /// Sample rate of the raw samples (matches the hardware input).
    private(set) var lastRecordingSampleRate: Double = 0

    /// Root directory for all TalkToMyMac data.
    static var dataDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TalkToMyMac", isDirectory: true)
    }

    /// Subdirectory where audio recordings are saved.
    static var recordingsDirectory: URL {
        dataDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }



    func start() throws {
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        lastRecordingSampleRate = recordingFormat.sampleRate
        print("[AudioCapture] Input format: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount), commonFormat=\(recordingFormat.commonFormat.rawValue)")

        // Reset in-memory buffer
        var accumulatedSamples: [Float] = []

        // Create recordings subdirectory
        let recordingsDir = Self.recordingsDirectory
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let fileName = "recording-\(UUID().uuidString).wav"
        let fileURL = recordingsDir.appendingPathComponent(fileName)
        lastRecordingPath = fileURL.path

        // PCM Int16 WAV output at the input node's sample rate
        guard let wavFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: recordingFormat.sampleRate,
            channels: recordingFormat.channelCount,
            interleaved: true
        ) else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create WAV format"
            ])
        }

        audioFile = try AVAudioFile(forWriting: fileURL, settings: wavFormat.settings)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            // Write to disk
            try? self?.audioFile?.write(from: buffer)

            // Accumulate in memory (channel 0, float32)
            if let channelData = buffer.floatChannelData {
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                accumulatedSamples.append(contentsOf: samples)
            }
        }

        try engine.start()
        isRecording = true
        // Capture the local into the closure's capture list by storing a reference
        // to finalise once recording stops — see stop() below.
        self._accumulatingBuffer = { accumulatedSamples }
    }

    /// Closure that captures the local accumulation array from start().
    private var _accumulatingBuffer: (() -> [Float])?

    func stop() throws {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        isRecording = false

        // Snapshot the accumulated samples
        lastRecordingRawSamples = _accumulatingBuffer?()
        _accumulatingBuffer = nil
    }

    /// Throws away the most recent (already stopped) recording: drops the in-memory
    /// samples and deletes the WAV from disk, so a discarded dictation leaves no trace.
    func discardLastRecording() {
        lastRecordingRawSamples = nil
        if let path = lastRecordingPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        lastRecordingPath = nil
    }
}
