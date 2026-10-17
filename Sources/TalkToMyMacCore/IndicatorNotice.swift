import Foundation

/// A short message for the user, shown inside the floating indicator for `duration` seconds
/// with a bar counting down the time left, after which the indicator returns to its dot.
/// The general way the app tells the user something happened without opening a window.
public struct IndicatorNotice: Identifiable, Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case info
        case warning
        case error
    }

    /// Unique per notice, so a newer notice with the same text still restarts the countdown.
    public let id: UUID
    public let title: String
    public let message: String
    public let style: Style
    /// Seconds the notice stays up.
    public let duration: TimeInterval
    public let shownAt: Date

    public static let defaultDuration: TimeInterval = 10

    public init(title: String, message: String, style: Style,
                duration: TimeInterval = IndicatorNotice.defaultDuration, shownAt: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.message = message
        self.style = style
        self.duration = duration
        self.shownAt = shownAt
    }

    public var expiresAt: Date { shownAt.addingTimeInterval(duration) }

    /// How much of the countdown bar is left at `date`: 1 when shown, 0 once expired.
    public func remainingFraction(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let remaining = expiresAt.timeIntervalSince(date) / duration
        return min(max(remaining, 0), 1)
    }
}

/// Something that can show the user an `IndicatorNotice`. Callable from any thread;
/// implementations hop to the main actor themselves.
public protocol NoticePresenting: AnyObject, Sendable {
    func present(_ notice: IndicatorNotice)
}

public extension IndicatorNotice {
    /// Tells the user a remote formatting call failed, so the raw transcript was delivered,
    /// and that the provider is paused.
    static func formattingFailed(_ pause: FormattingPause, shownAt: Date = Date()) -> IndicatorNotice {
        var reason = pause.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.hasSuffix(".") { reason.removeLast() }
        return IndicatorNotice(title: "\(pause.provider.displayName) formatting failed",
                               message: "\(reason). Formatting is paused for 1 hour.",
                               style: .error, shownAt: shownAt)
    }

    /// Tells the user formatting ran past `FormattingDeadline.timeout`, so the text was
    /// pasted unformatted.
    static func formattingTimedOut(_ provider: FormattingProvider, shownAt: Date = Date()) -> IndicatorNotice {
        let seconds = FormattingDeadline.timeout.components.seconds
        return IndicatorNotice(title: "LLM formatting failed",
                               message: "\(provider.displayName) didn't respond within \(seconds) seconds. "
                                   + "Pasted without formatting.",
                               style: .error, shownAt: shownAt)
    }
}
