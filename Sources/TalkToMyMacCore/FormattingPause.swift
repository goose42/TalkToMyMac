import Foundation

/// A remote formatting provider switched off for a while after a call to it failed, so a
/// broken key, outage or rate limit doesn't slow every dictation down. While active,
/// dictations are delivered without LLM formatting. The user can resume early in Settings.
public struct FormattingPause: Codable, Equatable, Sendable {
    public let provider: FormattingProvider
    /// Why the call failed, for Settings and the notice.
    public let reason: String
    public let until: Date

    /// How long a failure pauses its provider.
    public static let duration: TimeInterval = 60 * 60

    public init(provider: FormattingProvider, reason: String, until: Date) {
        self.provider = provider
        self.reason = reason
        self.until = until
    }

    /// The pause a formatting attempt calls for: one for a failed remote call, nil for a
    /// success or an on-device failure (which costs nothing to retry).
    public static func after(_ outcome: FormattingOutcome, at now: Date = Date()) -> FormattingPause? {
        guard outcome.text == nil, outcome.model.isRemote else { return nil }
        return FormattingPause(provider: outcome.model.provider,
                               reason: outcome.failure ?? "The request failed",
                               until: now.addingTimeInterval(duration))
    }

    /// Whether formatting with `provider` should be skipped at `date`.
    public func isActive(for provider: FormattingProvider, at date: Date = Date()) -> Bool {
        provider == self.provider && date < until
    }
}
