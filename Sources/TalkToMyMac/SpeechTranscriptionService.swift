import AVFoundation
import CoreMedia
import Observation
import Speech
import TalkToMyMacCore

/// Speech-to-text using macOS 26's on-device `SpeechAnalyzer` / `SpeechTranscriber`.
///
/// Runs fully on-device; unlike the old `SFSpeechRecognizer`-based service this needs no
/// `requestAuthorization` call. Model assets are managed through `AssetInventory` and are
/// downloaded on demand (see `prepare()`).
///
/// `@Observable` so the Settings UI reflects status changes automatically — this replaces
/// the manual `refreshTick`/polling hack the old settings screen needed because neither
/// prior STT service exposed observable state. `@Observable`'s change tracking is
/// thread-agnostic (unlike the old Combine-based `ObservableObject`), so this deliberately
/// isn't actor-isolated: `transcribe(samples:sampleRate:)` does real work across `await`
/// points and shouldn't be pinned to the main actor.
/// `@unchecked Sendable`: this type is deliberately shared between the main-actor Settings
/// UI (reads `isReady`/`isDownloading`/`loadError`/`resolvedLocale`) and the non-isolated
/// `RecorderController` pipeline (calls `transcribe`). Nothing here does unsynchronized
/// concurrent mutation — status updates are simple value writes driven by a single
/// in-flight `prepare()`/`transcribe()` call at a time — so the isolation checker's
/// region-transfer analysis is overly conservative for this specific, effectively-serial
/// usage pattern.
@available(macOS 26.0, *)
@Observable
final class SpeechTranscriptionService: SpeechTranscribing, @unchecked Sendable {
    private(set) var resolvedLocale: Locale

    private(set) var isReady = false
    private(set) var isDownloading = false
    private(set) var loadError: String?

    init(preferredLocale: Locale = .current) {
        // Placeholder until `prepare()` resolves a locale the transcriber actually supports.
        self.resolvedLocale = preferredLocale
    }

    /// Builds a transcriber for the resolved locale.
    ///
    /// A `SpeechTranscriber`'s `results` is a single-consumer `AsyncThrowingStream`: awaiting
    /// `next()` on it from two tasks traps with "attempt to await next() on more than one
    /// task". So instances are never reused across transcriptions — each call gets its own.
    private func makeTranscriber(preset: SpeechTranscriber.Preset = .transcription) -> SpeechTranscriber {
        SpeechTranscriber(locale: resolvedLocale, preset: preset)
    }

    /// Resolves the best-supported locale, checks/downloads the on-device model asset, and
    /// marks the service ready. Safe to call more than once (e.g. on relaunch).
    func prepare() async {
        guard SpeechTranscriber.isAvailable else {
            isReady = false
            loadError = "Speech recognition unavailable on this device"
            return
        }

        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: resolvedLocale)
            ?? Locale(identifier: "en_US")
        resolvedLocale = locale

        let status = await AssetInventory.status(forModules: [makeTranscriber()])
        switch status {
        case .installed:
            isReady = true
            loadError = nil
        case .supported, .downloading:
            await downloadModelIfNeeded()
        case .unsupported:
            isReady = false
            loadError = "Locale \(locale.identifier) not supported"
        @unknown default:
            isReady = false
            loadError = "Unknown asset status"
        }
    }

    /// Downloads and installs the on-device speech model, then reserves the locale so it
    /// stays resident. Safe to call directly (e.g. from a Settings "Download" button).
    func downloadModelIfNeeded() async {
        // `prepare()` is called from both app launch and the Settings window's `.task`, so
        // guard against kicking off a second concurrent install request.
        guard !isDownloading else { return }
        isDownloading = true
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [makeTranscriber()]) {
                try await request.downloadAndInstall()
            }
            _ = try? await AssetInventory.reserve(locale: resolvedLocale)
            isReady = true
            loadError = nil
            isDownloading = false
        } catch {
            isReady = false
            isDownloading = false
            loadError = "Download failed: \(error.localizedDescription)"
        }
    }

    func transcribe(samples: [Float], sampleRate: Double) async -> TranscriptionOutcome? {
        let segments = await analyze(samples: samples, sampleRate: sampleRate, preset: .transcription)
        let text = segments?.map { String($0.text.characters) }.joined() ?? ""
        return text.isEmpty ? nil : TranscriptionOutcome(text: text, engine: .appleOnDevice)
    }

    /// The engine's n-best list. Short clips usually come back as a single segment; when
    /// there are several, each segment's alternatives are combined with the other
    /// segments' best text, so every candidate still covers the whole clip.
    func transcribeAlternatives(samples: [Float], sampleRate: Double) async -> [String] {
        guard let segments = await analyze(samples: samples, sampleRate: sampleRate,
                                           preset: .transcriptionWithAlternatives) else { return [] }
        let best = segments.map { String($0.text.characters) }
        var candidates = [best.joined()]
        for (index, segment) in segments.enumerated() {
            for alternative in segment.alternatives {
                var combined = best
                combined[index] = String(alternative.characters)
                candidates.append(combined.joined())
            }
        }
        var seen = Set<String>()
        return candidates.filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty && seen.insert($0).inserted
        }
    }

    /// Runs the clip through a fresh transcriber and returns its final results, or nil if
    /// the service isn't ready or analysis failed.
    private func analyze(samples: [Float], sampleRate: Double,
                         preset: SpeechTranscriber.Preset) async -> [SpeechTranscriber.Result]? {
        guard isReady else {
            print("[SpeechTranscriptionService] Not ready")
            return nil
        }

        // A fresh transcriber per call: `results` is single-consumer, so reusing one
        // instance across recordings traps once a second iteration starts.
        let transcriber = makeTranscriber(preset: preset)

        guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            print("[SpeechTranscriptionService] No compatible audio format for transcriber")
            return nil
        }

        let buffer: AVAudioPCMBuffer
        do {
            buffer = try AudioFormatConverter.convert(samples: samples, sampleRate: sampleRate, to: targetFormat)
        } catch {
            print("[SpeechTranscriptionService] Audio conversion failed: \(error)")
            return nil
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        // Start consuming results before kicking off analysis so nothing is missed.
        let resultsTask = Task<[SpeechTranscriber.Result], Never> {
            var segments: [SpeechTranscriber.Result] = []
            do {
                for try await result in transcriber.results where result.isFinal {
                    segments.append(result)
                }
            } catch {
                print("[SpeechTranscriptionService] Results stream error: \(error)")
            }
            return segments
        }

        do {
            try await analyzer.start(inputSequence: stream)
            continuation.yield(AnalyzerInput(buffer: buffer))
            continuation.finish()
            // Required: finishing the *input* sequence does not finish the analyzer, and the
            // module's `results` stream stays open until the analyzer itself finishes. Without
            // this, `resultsTask` below never terminates and the await deadlocks.
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            print("[SpeechTranscriptionService] Analysis failed: \(error)")
            continuation.finish()
            await analyzer.cancelAndFinishNow()
            resultsTask.cancel()
            return nil
        }

        return await resultsTask.value
    }
}
