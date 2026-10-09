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

    /// Whether transcripts leave the Mac — and so whether calls are metered by tokens.
    public var isRemote: Bool { provider != .appleOnDevice }

    public var displayName: String {
        switch provider {
        case .appleOnDevice: return "Apple Intelligence (on-device)"
        case .groq:          return "Groq · \(modelID)"
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

    public init(model: FormattingModel, text: String?, usage: TokenUsage? = nil) {
        self.model = model
        self.text = text
        self.usage = usage
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
    /// Groq's published price when this version was written
    /// (https://console.groq.com/docs/model/openai/gpt-oss-20b). Users can override it in
    /// Settings when Groq's pricing changes.
    var listPrice: TokenPrice {
        switch self {
        case .gptOss20b: return TokenPrice(inputPerMillion: 0.075, cachedInputPerMillion: 0.0375, outputPerMillion: 0.30)
        }
    }
}
