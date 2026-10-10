import AVFoundation
import FluidAudio
import Foundation
import Observation
import TalkToMyMacCore

/// Speech-to-text using NVIDIA's Parakeet TDT 0.6B v3, converted to Core ML and run on the
/// Neural Engine through FluidAudio. Unlike Apple's model, the app downloads and hosts this one
/// itself: the files live under Application Support, and the model only occupies memory
/// between `load()` and `unload()`.
///
/// `@unchecked Sendable` for the same reason as `SpeechTranscriptionService`: shared between
/// the main-actor Settings UI (reads `state`) and the non-isolated recording pipeline (calls
/// `transcribe`), with status updates driven by one user action at a time.
@available(macOS 26.0, *)
@Observable
final class ParakeetTranscriptionService: SpeechTranscribing, @unchecked Sendable {
    private(set) var state: ExternalModelState
    /// Fraction of the download completed, while `state` is `.downloading`.
    private(set) var downloadProgress: Double = 0

    @ObservationIgnored private var manager: AsrManager?

    /// Where the model files live. FluidAudio keeps each model in a folder named after its
    /// Hugging Face repo, next to the directory it's given, so this is named to match.
    static let modelDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TalkToMyMac/Models/parakeet-tdt-0.6b-v3-coreml", isDirectory: true)

    /// Parakeet expects 16 kHz mono Float32.
    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    init() {
        state = AsrModels.modelsExist(at: Self.modelDirectory, version: .v3) ? .downloaded : .notDownloaded
    }

    var isReady: Bool { state == .ready }

    /// Bytes the model files take up on disk, or nil if they aren't there.
    var sizeOnDisk: Int64? {
        guard state.isOnDisk else { return nil }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
        guard let files = FileManager.default.enumerator(at: Self.modelDirectory, includingPropertiesForKeys: keys)
        else { return nil }
        return files.compactMap { try? ($0 as? URL)?.resourceValues(forKeys: Set(keys)).totalFileAllocatedSize }
            .reduce(Int64(0)) { $0 + Int64($1) }
    }

    /// Downloads the model files, then loads them.
    func download() async {
        guard state == .notDownloaded || isFailed else { return }
        state = .downloading
        downloadProgress = 0
        do {
            try await AsrModels.download(to: Self.modelDirectory, version: .v3) { [weak self] progress in
                Task { @MainActor in self?.downloadProgress = progress.fractionCompleted }
            }
            state = .downloaded
        } catch {
            state = .failed("Download failed: \(error.localizedDescription)")
            return
        }
        await load()
    }

    /// Loads the downloaded model into memory so it can transcribe.
    func load() async {
        guard state == .downloaded || (isFailed && AsrModels.modelsExist(at: Self.modelDirectory, version: .v3))
        else { return }
        state = .loading
        do {
            let models = try await AsrModels.load(from: Self.modelDirectory, version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            self.manager = manager
            state = .ready
        } catch {
            state = .failed("Couldn't load the model: \(error.localizedDescription)")
        }
    }

    /// Frees the model's memory, keeping its files on disk.
    func unload() async {
        guard let manager else {
            if state == .ready || state == .loading { state = .downloaded }
            return
        }
        self.manager = nil
        await manager.cleanup()
        state = .downloaded
    }

    /// Unloads the model and deletes its files.
    func deleteFiles() async {
        await unload()
        do {
            try FileManager.default.removeItem(at: Self.modelDirectory)
            state = .notDownloaded
        } catch {
            state = .failed("Couldn't delete the model files: \(error.localizedDescription)")
        }
    }

    func transcribe(samples: [Float], sampleRate: Double) async -> TranscriptionOutcome? {
        guard let manager else {
            print("[ParakeetTranscriptionService] Not loaded")
            return nil
        }
        do {
            let buffer = try AudioFormatConverter.convert(samples: samples, sampleRate: sampleRate, to: Self.targetFormat)
            let resampled = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            var decoderState = TdtDecoderState.make()
            let result = try await manager.transcribe(resampled, decoderState: &decoderState)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : TranscriptionOutcome(text: text, engine: .parakeetTDTv3)
        } catch {
            print("[ParakeetTranscriptionService] Transcription failed: \(error)")
            return nil
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
