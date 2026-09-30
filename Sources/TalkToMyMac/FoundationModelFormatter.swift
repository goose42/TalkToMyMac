import FoundationModels
import TalkToMyMacCore

/// Formats a raw transcript using Apple's on-device Foundation Models
/// (`SystemLanguageModel`). Any failure — the model being unavailable, a guardrail
/// refusal, a timeout, or a thrown `GenerationError` — returns `nil` rather than throwing,
/// so `RecorderController.processRecording` falls back to delivering the raw transcript.
/// `@unchecked Sendable`: shared between the main-actor Settings UI (reads `availability`)
/// and the non-isolated `RecorderController` pipeline (calls `format(raw:)`). `model` and
/// `settings` are only ever read, not mutated, from this class.
@available(macOS 26.0, *)
final class FoundationModelFormatter: TextFormatting, @unchecked Sendable {
    /// `.permissiveContentTransformations` is deliberately used instead of `.default`: this
    /// formatter only ever transforms text the user already spoke, and the default
    /// guardrails intermittently refuse otherwise-innocuous dictation for that use case.
    private let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    private let settings: FormattingSettings
    private let responseTimeout: Duration

    /// Current model availability, surfaced by Settings.
    var availability: SystemLanguageModel.Availability { model.availability }

    init(settings: FormattingSettings, responseTimeout: Duration = .seconds(15)) {
        self.settings = settings
        self.responseTimeout = responseTimeout
    }

    func shouldFormat(wordCount: Int) -> Bool {
        guard settings.skipShortDictations, wordCount <= settings.formattingWordThreshold else { return true }
        print("[FoundationModelFormatter] Skipping formatting: \(wordCount) word(s) "
              + "doesn't exceed the \(settings.formattingWordThreshold)-word threshold")
        return false
    }

    func format(raw: String) async -> String? {
        guard settings.isEnabled else { return nil }
        guard case .available = model.availability else {
            print("[FoundationModelFormatter] Model unavailable: \(model.availability)")
            return nil
        }

        // A fresh session per dictation — no context should bleed between utterances.
        let session = LanguageModelSession(model: model, instructions: settings.resolvedInstructions)
        let prompt = """
        Reformat the dictated text between the tags below. Output only the reformatted \
        text, with no preamble, quotation marks, or explanation.

        <text>
        \(raw)
        </text>
        """
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
