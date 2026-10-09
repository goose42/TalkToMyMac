import Foundation
import TalkToMyMacCore

/// Formats a raw transcript with a model hosted on Groq, via its Responses API. Like
/// `FoundationModelFormatter`, any failure — no API key, a network error, a timeout, or an
/// API error — returns `nil`, so the pipeline falls back to delivering the raw transcript.
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

    func format(raw: String) async -> String? {
        guard settings.isEnabled else { return nil }
        do {
            let text = try await respond(instructions: settings.resolvedInstructions,
                                         input: FormattingInstructions.userPrompt(transcript: raw))
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            print("[GroqFormatter] \(settings.groqModel.rawValue) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Formats a short sample with the saved key and selected model, for Settings to confirm
    /// the key works. Returns the formatted sample or the reason it failed.
    func testConnection() async -> Result<String, Error> {
        do {
            let text = try await respond(instructions: settings.resolvedInstructions,
                                         input: FormattingInstructions.userPrompt(transcript: "testing one two three"))
            return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .failure(error)
        }
    }

    private func respond(instructions: String, input: String) async throws -> String {
        guard let apiKey = keyStore.load(), !apiKey.isEmpty else { throw GroqFormatterError.noAPIKey }
        let request = GroqResponses.makeRequest(apiKey: apiKey, model: settings.groqModel,
                                                instructions: instructions, input: input)
        let (data, _) = try await session.data(for: request)
        // Error responses carry a JSON `error` object, which `parseOutputText` surfaces.
        return try GroqResponses.parseOutputText(data)
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
