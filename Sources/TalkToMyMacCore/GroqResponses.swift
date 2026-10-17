import Foundation

/// Models offered for Groq formatting. The raw value is Groq's model ID.
public enum GroqModel: String, CaseIterable, Hashable, Sendable {
    case gptOss20b = "openai/gpt-oss-20b"
    case gptOss120b = "openai/gpt-oss-120b"
    case llama31_8bInstant = "llama-3.1-8b-instant"
    case llama33_70bVersatile = "llama-3.3-70b-versatile"

    public static let `default`: GroqModel = .gptOss20b

    public var displayName: String {
        switch self {
        case .gptOss20b:            return "GPT-OSS 20B"
        case .gptOss120b:           return "GPT-OSS 120B"
        case .llama31_8bInstant:    return "Llama 3.1 8B Instant"
        case .llama33_70bVersatile: return "Llama 3.3 70B Versatile"
        }
    }

    /// Whether the model takes a reasoning effort. Llama models don't reason and Groq
    /// rejects the parameter for them.
    public var supportsReasoning: Bool {
        switch self {
        case .gptOss20b, .gptOss120b:                  return true
        case .llama31_8bInstant, .llama33_70bVersatile: return false
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
    /// formatter; reasoning effort, for models that reason, is kept low since cleanup needs
    /// little thought and latency matters more.
    public static func makeRequest(apiKey: String, model: GroqModel,
                                   instructions: String, input: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = RequestBody(model: model.rawValue, instructions: instructions, input: input,
                               temperature: 0.2, maxOutputTokens: 2048, reasoning: model.supportsReasoning ? .init(effort: "low") : nil)
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    /// A successful response: the assistant's text and the tokens it cost.
    public struct Output: Equatable, Sendable {
        public let text: String
        public let usage: TokenUsage?
    }

    /// The assistant's text — every `output_text` part of every message item, joined;
    /// reasoning items (which gpt-oss models emit) are skipped — and the reported usage.
    public static func parse(_ data: Data) throws -> Output {
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
        return Output(text: parts.joined(), usage: response.usage?.tokenUsage)
    }

    /// The usage a response reports, whether or not it succeeded — failed calls can still
    /// be billed. Nil if the body isn't a response or carries no usage.
    public static func usage(in data: Data) -> TokenUsage? {
        (try? JSONDecoder().decode(ResponseBody.self, from: data))?.usage?.tokenUsage
    }

    private struct RequestBody: Encodable {
        struct Reasoning: Encodable { let effort: String }
        let model: String
        let instructions: String
        let input: String
        let temperature: Double
        let maxOutputTokens: Int
        let reasoning: Reasoning?

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
        struct Usage: Decodable {
            struct InputDetails: Decodable {
                let cachedTokens: Int?
                enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" }
            }
            struct OutputDetails: Decodable {
                let reasoningTokens: Int?
                enum CodingKeys: String, CodingKey { case reasoningTokens = "reasoning_tokens" }
            }
            let inputTokens: Int
            let outputTokens: Int
            let inputTokensDetails: InputDetails?
            let outputTokensDetails: OutputDetails?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case inputTokensDetails = "input_tokens_details"
                case outputTokensDetails = "output_tokens_details"
            }

            var tokenUsage: TokenUsage {
                TokenUsage(input: inputTokens, output: outputTokens,
                           reasoning: outputTokensDetails?.reasoningTokens ?? 0,
                           cached: inputTokensDetails?.cachedTokens ?? 0)
            }
        }
        let status: String?
        let error: APIError?
        let output: [Item]?
        let usage: Usage?
    }
}
