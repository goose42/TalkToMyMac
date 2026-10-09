import Foundation

/// Which model formats transcripts.
public enum FormattingProvider: String, CaseIterable, Hashable, Sendable {
    case appleOnDevice
    case groq

    /// The provider selected on first launch — on-device, so nothing leaves the Mac by default.
    public static let `default`: FormattingProvider = .appleOnDevice

    public var displayName: String {
        switch self {
        case .appleOnDevice: return "Apple Intelligence (on-device)"
        case .groq:          return "Groq"
        }
    }
}

/// Models offered for Groq formatting. The raw value is Groq's model ID.
public enum GroqModel: String, CaseIterable, Hashable, Sendable {
    case gptOss20b = "openai/gpt-oss-20b"

    public static let `default`: GroqModel = .gptOss20b

    public var displayName: String {
        switch self {
        case .gptOss20b: return "GPT-OSS 20B"
        }
    }
}

/// Why a Groq call produced no formatted text.
public enum GroqError: Error, Equatable, LocalizedError {
    /// Groq returned an error object; carries its message.
    case api(String)
    /// The response finished with a status other than "completed".
    case incomplete(String)
    /// A completed response with no message text.
    case noText

    public var errorDescription: String? {
        switch self {
        case .api(let message):       return message
        case .incomplete(let status): return "Response \(status)"
        case .noText:                 return "Response had no text"
        }
    }
}

/// Builds requests for, and reads responses from, Groq's OpenAI-compatible Responses API
/// (https://console.groq.com/docs/api-reference#responses-create).
public enum GroqResponses {
    public static let endpoint = URL(string: "https://api.groq.com/openai/v1/responses")!

    /// A POST that formats `input` under `instructions`. Sampling matches the on-device
    /// formatter; reasoning effort is kept low since cleanup needs little thought and
    /// latency matters more.
    public static func makeRequest(apiKey: String, model: GroqModel,
                                   instructions: String, input: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = RequestBody(model: model.rawValue, instructions: instructions, input: input,
                               temperature: 0.2, maxOutputTokens: 2048, reasoning: .init(effort: "low"))
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    /// The assistant's text: every `output_text` part of every message item, joined.
    /// Reasoning items (which gpt-oss models emit) are skipped.
    public static func parseOutputText(_ data: Data) throws -> String {
        let response = try JSONDecoder().decode(ResponseBody.self, from: data)
        if let message = response.error?.message {
            throw GroqError.api(message)
        }
        let status = response.status ?? "unknown"
        guard status == "completed" else { throw GroqError.incomplete(status) }

        let parts = (response.output ?? [])
            .filter { $0.type == "message" }
            .flatMap { $0.content ?? [] }
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
        guard !parts.isEmpty else { throw GroqError.noText }
        return parts.joined()
    }

    private struct RequestBody: Encodable {
        struct Reasoning: Encodable { let effort: String }
        let model: String
        let instructions: String
        let input: String
        let temperature: Double
        let maxOutputTokens: Int
        let reasoning: Reasoning

        enum CodingKeys: String, CodingKey {
            case model, instructions, input, temperature, reasoning
            case maxOutputTokens = "max_output_tokens"
        }
    }

    private struct ResponseBody: Decodable {
        struct APIError: Decodable { let message: String? }
        struct Item: Decodable {
            let type: String
            let content: [Part]?
        }
        struct Part: Decodable {
            let type: String
            let text: String?
        }
        let status: String?
        let error: APIError?
        let output: [Item]?
    }
}
