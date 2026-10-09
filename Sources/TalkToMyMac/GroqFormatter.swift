import Foundation
import TalkToMyMacCore

/// Formats a raw transcript with a model hosted on Groq, via its Responses API. Like
/// `FoundationModelFormatter`, any failure — no API key, a network error, a timeout, or an
/// API error — yields no text, so the pipeline falls back to delivering the raw transcript.
/// Token usage is reported whenever Groq returns it, for the Instrumentation tab.
/// `@unchecked Sendable`: shared between the Settings UI (`testConnection`) and the
/// recording pipeline; it holds only immutable references.
final class GroqFormatter: TextFormatting, @unchecked Sendable {
    private let settings: FormattingSettings
    private let keyStore: APIKeyStore
    private let session: URLSession

    init(settings: FormattingSettings, keyStore: APIKeyStore = .groq, responseTimeout: TimeInterval = 15) {
        self.settings = settings
        self.keyStore = keyStore
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = responseTimeout
        config.timeoutIntervalForResource = responseTimeout
        self.session = URLSession(configuration: config)
    }

    func format(raw: String) async -> FormattingOutcome {
        let model = settings.groqModel
        do {
            let output = try await respond(model: model, instructions: settings.resolvedInstructions,
                                           input: FormattingInstructions.userPrompt(transcript: raw))
            let trimmed = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return FormattingOutcome(model: .groq(model), text: trimmed.isEmpty ? nil : trimmed, usage: output.usage)
        } catch let failure as Failure {
            print("[GroqFormatter] \(model.rawValue) failed: \(failure.error.localizedDescription)")
            return FormattingOutcome(model: .groq(model), text: nil, usage: failure.usage)
        } catch {
            print("[GroqFormatter] \(model.rawValue) failed: \(error.localizedDescription)")
            return FormattingOutcome(model: .groq(model), text: nil)
        }
    }

    /// Formats a short sample with the saved key and selected model, for Settings to confirm
    /// the key works. Returns the formatted sample or the reason it failed.
    func testConnection() async -> Result<String, Error> {
        do {
            let output = try await respond(model: settings.groqModel, instructions: settings.resolvedInstructions,
                                           input: FormattingInstructions.userPrompt(transcript: "testing one two three"))
            return .success(output.text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let failure as Failure {
            return .failure(failure.error)
        } catch {
            return .failure(error)
        }
    }

    /// A response that couldn't be used, with whatever usage it still reported (and was
    /// billed for).
    private struct Failure: Error {
        let error: Error
        let usage: TokenUsage?
    }

    private func respond(model: GroqModel, instructions: String, input: String) async throws -> GroqResponses.Output {
        guard let apiKey = keyStore.load(), !apiKey.isEmpty else { throw GroqFormatterError.noAPIKey }
        let request = GroqResponses.makeRequest(apiKey: apiKey, model: model,
                                                instructions: instructions, input: input)
        let (data, _) = try await session.data(for: request)
        // Error responses carry a JSON `error` object, which `parse` surfaces.
        do {
            return try GroqResponses.parse(data)
        } catch {
            throw Failure(error: error, usage: GroqResponses.usage(in: data))
        }
    }
}

enum GroqFormatterError: LocalizedError {
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Groq API key saved"
        }
    }
}
