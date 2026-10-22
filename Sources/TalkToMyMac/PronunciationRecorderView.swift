import SwiftUI
import TalkToMyMacCore

/// Sheet that learns a dictionary term's "heard as" forms from the user's voice: they say
/// the term alone and then in a carrier sentence, `PronunciationProbe` transcribes both in
/// several voice variations, and every new mis-hearing is added to the entry.
@available(macOS 26.0, *)
struct PronunciationRecorderView: View {
    let editor: DictionaryEditor
    let id: UUID
    let transcriber: TranscriptionRouter
    let settings: FormattingSettings

    @Environment(\.dismiss) private var dismiss

    private enum Step: Equatable {
        case word
        case sentence
        case analyzing(done: Int, total: Int)
        case finished(added: [String])
        case failed(String)
    }

    @State private var step = Step.word
    @State private var capture = AudioCapture()
    @State private var isRecording = false
    @State private var level: Float = 0
    @State private var wordTake: PronunciationProbe.Take?

    private var written: String { editor.item(id)?.entry.written ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record Pronunciation")
                .font(.headline)
            content
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            HStack {
                Spacer()
                switch step {
                case .finished, .failed:
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                case .analyzing:
                    EmptyView()
                case .word, .sentence:
                    Button("Cancel", role: .cancel) {
                        stopCapture()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onDisappear { stopCapture() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .word:
            prompt(step: 1, Text("Say “\(written)” on its own, the way you'd say it while dictating."))
        case .sentence:
            prompt(step: 2, Text("Now say: “\(PronunciationProbe.carrierPrefix) **\(written)** "
                                 + "\(PronunciationProbe.carrierSuffix).”"))
        case .analyzing(let done, let total):
            VStack(alignment: .leading, spacing: 8) {
                Text("Trying \(total) voice variations…")
                ProgressView(value: Double(done), total: Double(max(total, 1)))
            }
        case .finished(let added):
            if added.isEmpty {
                Text("Transcription didn't hear anything that isn't already “\(written)” or in "
                     + "“Heard as” — nothing to add.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Added to “Heard as”:")
                    Text(added.joined(separator: ", "))
                        .fontWeight(.medium)
                        .textSelection(.enabled)
                    Text("Remove any that look wrong in the Heard as field.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func prompt(step number: Int, _ instruction: Text) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step \(number) of 2").font(.caption).foregroundStyle(.secondary)
            instruction
            HStack(spacing: 12) {
                Button(isRecording ? "Stop" : "Record", systemImage: isRecording ? "stop.fill" : "mic.fill") {
                    isRecording ? finishTake() : startCapture()
                }
                .keyboardShortcut(.defaultAction)
                ProgressView(value: Double(isRecording ? level : 0))
                    .frame(width: 120)
            }
        }
    }

    // MARK: Recording

    private func startCapture() {
        capture.inputDevice = { [settings] in settings.inputDevice }
        capture.onLevels = { levels in
            guard let latest = levels.last else { return }
            DispatchQueue.main.async { level = latest }
        }
        do {
            try capture.start()
            isRecording = true
        } catch {
            step = .failed("Couldn't start recording: \(error.localizedDescription)")
        }
    }

    /// Stops the current take and moves on: to the sentence after the word, to analysis
    /// after the sentence.
    private func finishTake() {
        guard let take = stopCapture() else {
            step = .failed("Nothing was recorded. Check microphone access in System Settings.")
            return
        }
        if step == .word {
            wordTake = take
            step = .sentence
        } else if let wordTake {
            analyze(word: wordTake, sentence: take)
        }
    }

    /// Stops recording if it's running and returns what was captured. Practice clips are
    /// deleted at once so they don't pile up with the dictation recordings.
    @discardableResult
    private func stopCapture() -> PronunciationProbe.Take? {
        guard isRecording else { return nil }
        isRecording = false
        try? capture.stop()
        defer { capture.discardLastRecording() }
        guard let samples = capture.lastRecordingRawSamples, !samples.isEmpty else { return nil }
        return PronunciationProbe.Take(samples: samples, sampleRate: capture.lastRecordingSampleRate)
    }

    // MARK: Analysis

    private func analyze(word: PronunciationProbe.Take, sentence: PronunciationProbe.Take) {
        guard transcriber.isReady else {
            step = .failed("The speech model isn't ready yet.")
            return
        }
        guard let entry = editor.item(id)?.entry else { return }
        step = .analyzing(done: 0, total: 0)

        Task {
            let probe = PronunciationProbe(transcriber: transcriber, pitchShifter: TimePitchShifter())
            let candidates = await probe.run(word: word, sentence: sentence, written: entry.written,
                                             existing: entry.soundsLike) { done, total in
                Task { @MainActor in
                    // A late update mustn't overwrite the result.
                    if case .analyzing = step { step = .analyzing(done: done, total: total) }
                }
            }
            let added = editor.addSoundsLike(candidates.map(\.text), to: id)
            step = .finished(added: added)
        }
    }
}
