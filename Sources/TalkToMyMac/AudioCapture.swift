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
        return files.filter { $0.pathExtension.lowercased() == "wav" }
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

        let onLevels = self.onLevels
        let levelChunkSize = max(Int(recordingFormat.sampleRate / 30), 1)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            // Write to disk
            try? self?.audioFile?.write(from: buffer)

            // Accumulate in memory (channel 0, float32)
            if let channelData = buffer.floatChannelData {
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                accumulatedSamples.append(contentsOf: samples)
                onLevels?(Self.levels(of: samples, chunkSize: levelChunkSize))
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

    /// RMS level of each `chunkSize` run of samples, mapped from -50…-10 dBFS onto 0…1
    /// (roughly silence to loud speech).
    private static func levels(of samples: [Float], chunkSize: Int) -> [Float] {
        stride(from: 0, to: samples.count, by: chunkSize).map { start in
            let chunk = samples[start..<min(start + chunkSize, samples.count)]
            let meanSquare = chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count)
            let db = 10 * log10(max(meanSquare, 1e-12))
            return min(max((db + 50) / 40, 0), 1)
        }
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
