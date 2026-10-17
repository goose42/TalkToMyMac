import Foundation

/// Which model formats transcripts.
public enum FormattingProvider: String, CaseIterable, Hashable, Codable, Sendable {
    case appleOnDevice
    case groq
    case openRouter

    /// The provider selected on first launch — on-device, so nothing leaves the Mac by default.
    public static let `default`: FormattingProvider = .appleOnDevice

    public var displayName: String {
        switch self {
        case .appleOnDevice: return "Apple Intelligence (on-device)"
        case .groq:          return "Groq"
        case .openRouter:    return "OpenRouter"
        }
    }

    /// Whether the provider has a settings page of its own (API key, model, prices). Apple's
    /// on-device model needs no setup.
    public var hasConfiguration: Bool {
        switch self {
        case .appleOnDevice: return false
        case .groq:          return true
        case .openRouter:    return true
        }
    }

    /// The providers with a settings page, in display order.
    public static var configurable: [FormattingProvider] { allCases.filter(\.hasConfiguration) }
}

/// A specific model on a specific provider — the unit formatting metrics are kept per.
public struct FormattingModel: Hashable, Sendable {
    public let provider: FormattingProvider
    /// The provider's own model ID, e.g. "openai/gpt-oss-20b".
    public let modelID: String

    public init(provider: FormattingProvider, modelID: String) {
        self.provider = provider
        self.modelID = modelID
    }

    /// Apple's on-device model, which has no public version identifier.
    public static let appleOnDevice = FormattingModel(provider: .appleOnDevice, modelID: "apple-on-device")

    public static func groq(_ model: GroqModel) -> FormattingModel {
        FormattingModel(provider: .groq, modelID: model.rawValue)
    }

    public static func openRouter(_ model: OpenRouterModel) -> FormattingModel {
        FormattingModel(provider: .openRouter, modelID: model.rawValue)
    }

    /// Whether transcripts leave the Mac — and so whether calls are metered by tokens.
    public var isRemote: Bool { provider != .appleOnDevice }

    public var displayName: String {
        switch provider {
        case .appleOnDevice: return "Apple Intelligence (on-device)"
        case .groq:          return "Groq · \(modelID)"
        case .openRouter:    return "OpenRouter · \(modelID)"
        }
    }
}

/// Tokens a remote model reported for one call. `reasoning` is part of `output` and
/// `cached` is part of `input`, as providers bill them.
public struct TokenUsage: Equatable, Sendable {
    public let input: Int
    public let output: Int
    public let reasoning: Int
    public let cached: Int

    public init(input: Int, output: Int, reasoning: Int, cached: Int) {
        self.input = input
        self.output = output
        self.reasoning = reasoning
        self.cached = cached
    }
}

/// What one formatting attempt produced, and which model made it.
public struct FormattingOutcome: Equatable, Sendable {
    public let model: FormattingModel
    /// The formatted text, or nil if the attempt failed and the raw transcript should be used.
    public let text: String?
    /// Tokens the provider reported, or nil if it didn't (on-device models, network failures).
    public let usage: TokenUsage?
    /// Why the attempt failed, for telling the user; nil on success.
    public let failure: String?

    public init(model: FormattingModel, text: String?, usage: TokenUsage? = nil, failure: String? = nil) {
        self.model = model
        self.text = text
        self.usage = usage
        self.failure = failure
    }
}

/// Token usage summed over a set of dictations, for cost tracking.
public struct TokenTotals: Equatable, Sendable {
    /// Dictations that reported usage.
    public let dictations: Int
    public let input: Int
    public let output: Int
    public let reasoning: Int
    public let cached: Int

    public init(dictations: Int, input: Int, output: Int, reasoning: Int, cached: Int) {
        self.dictations = dictations
        self.input = input
        self.output = output
        self.reasoning = reasoning
        self.cached = cached
    }

    /// Sums the dictations that reported usage; nil if none did.
    public static func sum(_ usages: [TokenUsage?]) -> TokenTotals? {
        let reported = usages.compactMap { $0 }
        guard !reported.isEmpty else { return nil }
        return TokenTotals(
            dictations: reported.count,
            input: reported.reduce(0) { $0 + $1.input },
            output: reported.reduce(0) { $0 + $1.output },
            reasoning: reported.reduce(0) { $0 + $1.reasoning },
            cached: reported.reduce(0) { $0 + $1.cached }
        )
    }

    public var total: Int { input + output }
    public var averageInput: Double { Double(input) / Double(dictations) }
    public var averageOutput: Double { Double(output) / Double(dictations) }
}

/// Words sent to and returned by a formatting model, summed over a set of dictations.
public struct WordTotals: Equatable, Sendable {
    public let dictations: Int
    /// Words in the raw transcripts sent to the model.
    public let input: Int
    /// Words in the text delivered after formatting.
    public let output: Int

    public init(dictations: Int, input: Int, output: Int) {
        self.dictations = dictations
        self.input = input
        self.output = output
    }

    public static func sum(_ counts: [(input: Int, output: Int)]) -> WordTotals {
        WordTotals(
            dictations: counts.count,
            input: counts.reduce(0) { $0 + $1.input },
            output: counts.reduce(0) { $0 + $1.output }
        )
    }
}

/// What a remote model charges, in US dollars per million tokens.
public struct TokenPrice: Equatable, Codable, Sendable {
    public var inputPerMillion: Double
    /// Input tokens served from the provider's prompt cache, usually discounted.
    public var cachedInputPerMillion: Double
    public var outputPerMillion: Double

    public init(inputPerMillion: Double, cachedInputPerMillion: Double, outputPerMillion: Double) {
        self.inputPerMillion = inputPerMillion
        self.cachedInputPerMillion = cachedInputPerMillion
        self.outputPerMillion = outputPerMillion
    }
}

public extension TokenTotals {
    /// Dollars these tokens cost at `price`. Cached input is billed at the cached rate and
    /// the rest of the input at the full rate; reasoning is already counted in output.
    func cost(at price: TokenPrice) -> Double {
        let uncached = Double(input - cached) * price.inputPerMillion
        let cachedCost = Double(cached) * price.cachedInputPerMillion
        let outputCost = Double(output) * price.outputPerMillion
        return (uncached + cachedCost + outputCost) / 1_000_000
    }

    func averageCost(at price: TokenPrice) -> Double {
        cost(at: price) / Double(dictations)
    }
}

public extension GroqModel {
    /// Groq's published price when this version was written (https://groq.com/pricing).
    /// Llama models get no prompt-cache discount, so their cached rate is the input rate.
    /// Users can override it in Settings when Groq's pricing changes.
    var listPrice: TokenPrice {
        switch self {
        case .gptOss20b:            return TokenPrice(inputPerMillion: 0.075, cachedInputPerMillion: 0.0375, outputPerMillion: 0.30)
        case .gptOss120b:           return TokenPrice(inputPerMillion: 0.15, cachedInputPerMillion: 0.075, outputPerMillion: 0.60)
        case .llama31_8bInstant:    return TokenPrice(inputPerMillion: 0.05, cachedInputPerMillion: 0.05, outputPerMillion: 0.08)
        case .llama33_70bVersatile: return TokenPrice(inputPerMillion: 0.59, cachedInputPerMillion: 0.59, outputPerMillion: 0.79)
        }
    }
}

public extension OpenRouterModel {
    /// Every offered model is one of OpenRouter's `:free` variants. Users can still set a
    /// price in Settings if they switch to a paid route.
    var listPrice: TokenPrice {
        TokenPrice(inputPerMillion: 0, cachedInputPerMillion: 0, outputPerMillion: 0)
    }
}
