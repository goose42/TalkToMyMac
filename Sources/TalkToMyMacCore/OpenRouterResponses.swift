import Foundation

/// Models offered for OpenRouter formatting. The raw value is OpenRouter's model ID; all
/// are `:free` variants.
public enum OpenRouterModel: String, CaseIterable, Hashable, Sendable {
    case nemotron3Ultra = "nvidia/nemotron-3-ultra-550b-a55b:free"
    case nemotron35Lightning = "nvidia/nemotron-3.5-lightning:free"
    case inklingSmall = "thinkingmachines/inkling-small:free"
    case gemma4 = "google/gemma-4-26b-a4b-it:free"
    case northMiniCode = "cohere/north-mini-code:free"
    case lfm25 = "liquid/lfm-2.5-2.6b:free"

    /// A fast model, since cleanup latency is felt on every dictation.
    public static let `default`: OpenRouterModel = .nemotron35Lightning

    public var displayName: String {
        switch self {
        case .nemotron3Ultra:      return "Nemotron 3 Ultra 550B"
        case .nemotron35Lightning: return "Nemotron 3.5 Lightning"
        case .inklingSmall:        return "Inkling Small"
        case .gemma4:              return "Gemma 4 26B"
        case .northMiniCode:       return "North Mini Code"
        case .lfm25:               return "LFM 2.5 2.6B"
        }
    }
}

/// Why an OpenRouter call produced no formatted text.
public enum OpenRouterError: Error, Equatable, LocalizedError {
    /// OpenRouter or the upstream provider returned an error; carries its message.
    case api(String)
    /// The completion stopped for a reason other than finishing, e.g. "length".
    case incomplete(String)
    /// A finished completion with no message text.
    case noText

    public var errorDescription: String? {
        switch self {
        case .api(let message):       return message
        case .incomplete(let reason): return "Response stopped: \(reason)"
        case .noText:                 return "Response had no text"
        }
    }
}

/// Builds requests for, and reads responses from, OpenRouter's OpenAI-compatible Chat
/// Completions API (https://openrouter.ai/docs/api_reference/overview).
public enum OpenRouterResponses {
    public static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// A POST that formats `input` under `instructions`, sent as the system and user
    /// messages. Sampling matches the other formatters.
    public static func makeRequest(apiKey: String, model: OpenRouterModel,
                                   instructions: String, input: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Attributes calls to the app on OpenRouter's dashboard.
        request.setValue("TalkToMyMac", forHTTPHeaderField: "X-OpenRouter-Title")
        let body = RequestBody(model: model.rawValue,
                               messages: [.init(role: "system", content: instructions),
                                          .init(role: "user", content: input)],
                               temperature: 0.2, maxTokens: 2048)
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    /// A successful response: the assistant's text and the tokens it cost.
    public struct Output: Equatable, Sendable {
        public let text: String
        public let usage: TokenUsage?
    }

    /// The first choice's message content and the reported usage. `statusCode` is the HTTP
    /// status, used to explain failures whose body carries no error object.
    public static func parse(_ data: Data, statusCode: Int) throws -> Output {
        let response: ResponseBody
        do {
            response = try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            if let message = statusMessage(statusCode) { throw OpenRouterError.api(message) }
            throw error
        }
        if let message = response.error?.message {
            throw OpenRouterError.api(message)
        }
        if let message = statusMessage(statusCode) { throw OpenRouterError.api(message) }

        guard let choice = response.choices?.first else { throw OpenRouterError.noText }
        if let message = choice.error?.message {
            throw OpenRouterError.api(message)
        }
        switch choice.finishReason {
        case "error":  throw OpenRouterError.api("The model returned an error")
        case "length": throw OpenRouterError.incomplete("length")
        default:       break
        }
        guard let text = choice.message?.content, !text.isEmpty else { throw OpenRouterError.noText }
        return Output(text: text, usage: response.usage?.tokenUsage)
    }

    /// The usage a response reports, whether or not it succeeded. Nil if the body isn't a
    /// completion or carries no usage.
    public static func usage(in data: Data) -> TokenUsage? {
        (try? JSONDecoder().decode(ResponseBody.self, from: data))?.usage?.tokenUsage
    }

    /// A readable explanation of a failing HTTP status, or nil for success.
    private static func statusMessage(_ statusCode: Int) -> String? {
        switch statusCode {
        case 200..<300: return nil
        case 401:       return "Invalid OpenRouter API key (HTTP 401)"
        case 402:       return "OpenRouter account has insufficient credits (HTTP 402)"
        case 429:       return "Rate limited by OpenRouter (HTTP 429)"
        default:        return "OpenRouter returned HTTP \(statusCode)"
        }
    }

    private struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        let temperature: Double
        let maxTokens: Int

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case maxTokens = "max_tokens"
        }
    }

    private struct ResponseBody: Decodable {
        struct APIError: Decodable { let message: String? }
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let finishReason: String?
            let message: Message?
            let error: APIError?

            enum CodingKeys: String, CodingKey {
                case message, error
                case finishReason = "finish_reason"
            }
        }
        struct Usage: Decodable {
            struct PromptDetails: Decodable {
                let cachedTokens: Int?
                enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" }
            }
            struct CompletionDetails: Decodable {
                let reasoningTokens: Int?
                enum CodingKeys: String, CodingKey { case reasoningTokens = "reasoning_tokens" }
            }
            let promptTokens: Int
            let completionTokens: Int
            let promptTokensDetails: PromptDetails?
            let completionTokensDetails: CompletionDetails?

            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case promptTokensDetails = "prompt_tokens_details"
                case completionTokensDetails = "completion_tokens_details"
            }

            var tokenUsage: TokenUsage {
                TokenUsage(input: promptTokens, output: completionTokens,
                           reasoning: completionTokensDetails?.reasoningTokens ?? 0,
                           cached: promptTokensDetails?.cachedTokens ?? 0)
            }
        }
        let error: APIError?
        let choices: [Choice]?
        let usage: Usage?
    }
}
