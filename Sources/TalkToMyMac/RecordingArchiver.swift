import AVFoundation
import TalkToMyMacCore

/// Saves finished dictations to the recordings directory as 16 kHz mono AAC (`.m4a`, ~32 kbps,
/// roughly 240 KB a minute). Encoding runs on a low-priority serial queue, so `archive` returns
/// at once and never competes with the audio thread or the pipeline.
final class RecordingArchiver: RecordingArchiving, Sendable {
    private let queue = DispatchQueue(label: "com.talktomymac.recording-archiver", qos: .utility)

    /// 16 kHz is all the transcribers use, so storing more would only cost space.
    private static let sampleRate: Double = 16_000
    private static let bitRate = 32_000

    func archive(samples: [Float], sampleRate: Double, id: UUID) {
        guard !samples.isEmpty, sampleRate > 0 else { return }
        queue.async {
            do {
                let url = try Self.encode(samples: samples, sampleRate: sampleRate, id: id)
                print("[Archiver] Saved \(url.lastPathComponent)")
            } catch {
                print("[Archiver] Failed to save recording: \(error)")
            }
        }
    }

    private static func encode(samples: [Float], sampleRate: Double, id: UUID) throws -> URL {
        guard let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
                                            channels: 1, interleaved: false) else {
            throw AudioFormatConverter.ConversionError.formatCreationFailed
        }
        let buffer = try AudioFormatConverter.convert(samples: samples, sampleRate: sampleRate, to: pcmFormat)

        let directory = AudioCapture.recordingsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = AudioCapture.recordingFileName(id: id.uuidString)
        // Written under a hidden name and renamed once complete, so the Storage pane (which
        // skips hidden files) never counts a half-written recording.
        let partial = directory.appendingPathComponent("." + name)
        let final = directory.appendingPathComponent(name)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: Self.bitRate,
        ]
        do {
            // Scoped so the file is closed, and its header finalised, before the rename.
            try {
                let file = try AVAudioFile(forWriting: partial, settings: settings,
                                           commonFormat: .pcmFormatFloat32, interleaved: false)
                try file.write(from: buffer)
            }()
            try FileManager.default.moveItem(at: partial, to: final)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        return final
    }
}
