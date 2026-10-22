import Foundation

/// Tracks the floating indicator being hidden for a while. Pure state; the caller schedules
/// the wake-up and applies the visibility.
public struct IndicatorSnooze: Equatable, Sendable {
    public static let hideDuration: TimeInterval = 3600

    private var until: Date?

    public init() {}

    public mutating func snooze(for duration: TimeInterval, now: Date = Date()) {
        until = now.addingTimeInterval(duration)
    }

    public mutating func wake() {
        until = nil
    }

    public func isSnoozed(at date: Date = Date()) -> Bool {
        remaining(at: date) != nil
    }

    /// Seconds left, or nil if not snoozed.
    public func remaining(at date: Date = Date()) -> TimeInterval? {
        guard let until, until > date else { return nil }
        return until.timeIntervalSince(date)
    }
}
