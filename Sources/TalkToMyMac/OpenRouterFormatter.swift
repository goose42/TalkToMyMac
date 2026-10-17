import Foundation
import TalkToMyMacCore

/// Formats a raw transcript with a model routed through OpenRouter, via its Chat Completions
/// API. Like `GroqFormatter`, any failure — no API key, a network error, a timeout, a rate
/// limit, or an API error — yields no text, so the pipeline falls back to delivering the raw
/// transcript. Token usage is reported whenever OpenRouter returns it.
/// `@unchecked Sendable`: shared between the Settings UI (`testConnection`) and the
/// recording pipeline; it holds only immutable references.
final class OpenRouterFormatter: TextFormatting, @unchecked Sendable {
    private let settings: FormattingSettings
    private let keyStore: APIKeyStore
    private let session: URLSession

    // Free models are often queued behind paid traffic, so allow longer than Groq's 15s.
    init(settings: FormattingSettings, keyStore: APIKeyStore = .openRouter, responseTimeout: TimeInterval = 30) {
        self.settings = settings
        self.keyStore = keyStore
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = responseTimeout
        config.timeoutIntervalForResource = responseTimeout
        self.session = URLSession(configuration: config)
    }

    func format(raw: String) async -> FormattingOutcome {
        let model = settings.openRouterModel
        do {
            let output = try await respond(model: model, instructions: settings.resolvedInstructions,
                                           input: FormattingInstructions.userPrompt(transcript: raw))
            let trimmed = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return FormattingOutcome(model: .openRouter(model), text: trimmed.isEmpty ? nil : trimmed, usage: output.usage,
                                     failure: trimmed.isEmpty ? "Response had no text" : nil)
        } catch let failure as Failure {
            print("[OpenRouterFormatter] \(model.rawValue) failed: \(failure.error.localizedDescription)")
            return FormattingOutcome(model: .openRouter(model), text: nil, usage: failure.usage,
                                     failure: failure.error.localizedDescription)
        } catch {
            print("[OpenRouterFormatter] \(model.rawValue) failed: \(error.localizedDescription)")
            return FormattingOutcome(model: .openRouter(model), text: nil, failure: error.localizedDescription)
        }
    }

    /// Formats a short sample with the saved key and selected model, for Settings to confirm
    /// the key works. Returns the formatted sample or the reason it failed.
    func testConnection() async -> Result<String, Error> {
        do {
            let output = try await respond(model: settings.openRouterModel, instructions: settings.resolvedInstructions,
                                           input: FormattingInstructions.userPrompt(transcript: "testing one two three"))
            return .success(output.text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let failure as Failure {
            return .failure(failure.error)
        } catch {
            return .failure(error)
        }
    }

    /// A response that couldn't be used, with whatever usage it still reported.
    private struct Failure: Error {
        let error: Error
        let usage: TokenUsage?
    }

    private func respond(model: OpenRouterModel, instructions: String,
                         input: String) async throws -> OpenRouterResponses.Output {
        guard let apiKey = keyStore.load(), !apiKey.isEmpty else { throw OpenRouterFormatterError.noAPIKey }
        let request = OpenRouterResponses.makeRequest(apiKey: apiKey, model: model,
                                                      instructions: instructions, input: input)
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
        do {
            return try OpenRouterResponses.parse(data, statusCode: statusCode)
        } catch {
            throw Failure(error: error, usage: OpenRouterResponses.usage(in: data))
        }
    }
}

enum OpenRouterFormatterError: LocalizedError {
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No OpenRouter API key saved"
        }
    }
}
