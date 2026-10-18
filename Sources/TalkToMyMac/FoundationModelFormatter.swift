import FoundationModels
import Synchronization
import TalkToMyMacCore

/// Formats a raw transcript using Apple's on-device Foundation Models
/// (`SystemLanguageModel`). Any failure — the model being unavailable, a guardrail
/// refusal, a timeout, or a thrown `GenerationError` — yields no text rather than throwing,
/// so `RecorderController.processRecording` falls back to delivering the raw transcript.
///
/// Each recording gets a fresh session, created when the recording starts and prewarmed
/// right away and then every 4 s (the model's cache lapses after about 5 s), so the
/// instructions are still cached when the transcript arrives. The session is used for that
/// one transcript only.
/// `@unchecked Sendable`: shared between the main-actor Settings UI (reads `availability`)
/// and the non-isolated `RecorderController` pipeline (calls `format(raw:)`). `model` and
/// `settings` are only ever read, not mutated, from this class; `warm` is behind a lock.
@available(macOS 26.0, *)
final class FoundationModelFormatter: TextFormatting, @unchecked Sendable {
    /// `.permissiveContentTransformations` is deliberately used instead of `.default`: this
    /// formatter only ever transforms text the user already spoke, and the default
    /// guardrails intermittently refuse otherwise-innocuous dictation for that use case.
    private let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    private let settings: FormattingSettings
    private let responseTimeout: Duration
    private let warm = Mutex<WarmSession?>(nil)

    /// A session being kept warm for the recording in progress.
    private struct WarmSession {
        let session: LanguageModelSession
        let instructions: String
        let warmer: PeriodicWarmer
    }

    /// Current model availability, surfaced by Settings.
    var availability: SystemLanguageModel.Availability { model.availability }

    init(settings: FormattingSettings, responseTimeout: Duration = .seconds(15)) {
        self.settings = settings
        self.responseTimeout = responseTimeout
    }

    func beginWarming() {
        guard case .available = model.availability else { return }
        warm.withLock { warm in
            guard warm == nil else { return }
            let instructions = settings.resolvedInstructions
            let session = LanguageModelSession(model: model, instructions: instructions)
            let warmer = PeriodicWarmer {
                session.prewarm(promptPrefix: Prompt(FormattingInstructions.userPromptPrefix))
                print("[FoundationModelFormatter] prewarm")
            }
            warmer.start()
            warm = WarmSession(session: session, instructions: instructions, warmer: warmer)
        }
    }

    func endWarming() {
        takeWarmSession()?.warmer.stop()
    }

    /// Hands over the warm session, if any, so it's used no more than once.
    private func takeWarmSession() -> WarmSession? {
        warm.withLock { warm in
            defer { warm = nil }
            return warm
        }
    }

    func format(raw: String) async -> FormattingOutcome {
        FormattingOutcome(model: .appleOnDevice, text: await formattedText(raw: raw))
    }

    private func formattedText(raw: String) async -> String? {
        guard case .available = model.availability else {
            print("[FoundationModelFormatter] Model unavailable: \(model.availability)")
            return nil
        }

        // A fresh session per dictation — no context should bleed between utterances. Use the
        // one warmed during the recording unless the instructions changed since it was made.
        let instructions = settings.resolvedInstructions
        let warmed = takeWarmSession()
        warmed?.warmer.stop()
        let session = warmed.flatMap { $0.instructions == instructions ? $0.session : nil }
            ?? LanguageModelSession(model: model, instructions: instructions)
        let prompt = FormattingInstructions.userPrompt(transcript: raw)
        let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 2048)

        guard let content = await respondWithTimeout(session: session, prompt: prompt, options: options) else {
            return nil
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Races `session.respond` against a timeout so a hung/slow model never blocks delivery
    /// of the raw transcript.
    private func respondWithTimeout(
        session: LanguageModelSession,
        prompt: String,
        options: GenerationOptions
    ) async -> String? {
        enum RaceResult {
            case completed(String?)
            case timedOut
        }

        return await withTaskGroup(of: RaceResult.self) { group in
            group.addTask {
                do {
                    let response = try await session.respond(to: prompt, options: options)
                    return .completed(response.content)
                } catch {
                    print("[FoundationModelFormatter] respond(to:) failed: \(error)")
                    return .completed(nil)
                }
            }
            group.addTask { [responseTimeout = self.responseTimeout] in
                try? await Task.sleep(for: responseTimeout)
                return .timedOut
            }

            defer { group.cancelAll() }
            guard let first = await group.next() else { return nil }
            switch first {
            case .completed(let text):
                return text
            case .timedOut:
                print("[FoundationModelFormatter] respond(to:) timed out after \(responseTimeout)")
                return nil
            }
        }
    }
}
