import AVFoundation
import AudioToolbox
import OSLog
import TalkToMyMacCore

/// Captures microphone audio via AVAudioEngine into memory. Nothing is written while recording;
/// finished dictations are saved afterwards by `RecordingArchiver`.
final class AudioCapture: AudioRecording {
    private var engine = AVAudioEngine()
    /// UID of the microphone `engine` was pointed at, or nil if it follows the system default.
    private var engineDeviceUID: String?
    private(set) var isRecording = false
    private let logger = Logger(subsystem: "com.talktomymac.dictate", category: "AudioCapture")

    /// Which microphone to record from, read at the start of each recording.
    var inputDevice: () -> InputDeviceSelection = { .systemDefault }

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


    /// Points the engine at the chosen microphone, falling back to the system default when
    /// it isn't connected. A fresh engine is made whenever the device changes, since one that
    /// has already run keeps its old input format.
    private func routeInput() {
        let uid = inputDevice().deviceUID(connected: AudioDevices.list(.input).map(\.uid))
        if case .device(let chosen) = inputDevice(), uid == nil {
            logger.notice("Chosen microphone \(chosen, privacy: .public) isn't connected; using the system default")
        }
        guard uid != engineDeviceUID else { return }
        engine = AVAudioEngine()
        engineDeviceUID = nil
        guard let uid, let device = AudioDevices.device(uid: uid),
              let unit = engine.inputNode.audioUnit else { return }
        var id = device
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status == noErr {
            engineDeviceUID = uid
        } else {
            logger.error("Couldn't select microphone \(uid, privacy: .public): \(status)")
        }
    }

    func start() throws {
        routeInput()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        lastRecordingSampleRate = recordingFormat.sampleRate
        print("[AudioCapture] Input format: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount), commonFormat=\(recordingFormat.commonFormat.rawValue)")

        // Reset in-memory buffer
        var accumulatedSamples: [Float] = []

        let onLevels = self.onLevels
        let levelChunkSize = max(Int(recordingFormat.sampleRate / 30), 1)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
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

    /// Throws away the most recent (already stopped) recording. It was never written to
    /// disk, so dropping the in-memory samples leaves no trace.
    func discardLastRecording() {
        lastRecordingRawSamples = nil
    }
}
