import Foundation
import Synchronization

/// Runs `action` on a background task as soon as it's started, then again every `interval`
/// until stopped, or until `maxDuration` has passed since starting. Used to keep the on-device
/// model's prewarmed prompt cached for the length of a recording, since the cache lapses
/// after a few seconds; the cap stops it from running indefinitely when a transcript is left
/// in review.
public final class PeriodicWarmer: Sendable {
    /// Longer than any recording seen in practice (the longest so far was 86 s).
    public static let defaultMaxDuration: Duration = .seconds(120)

    private let interval: Duration
    private let maxDuration: Duration
    private let action: @Sendable () -> Void
    private let task = Mutex<Task<Void, Never>?>(nil)

    public init(interval: Duration = .seconds(4), maxDuration: Duration = defaultMaxDuration,
                action: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.maxDuration = maxDuration
        self.action = action
    }

    deinit { stop() }

    /// Starts the loop. Does nothing if it has already been started, even if it has since
    /// reached `maxDuration`.
    public func start() {
        task.withLock { task in
            guard task == nil else { return }
            task = Task.detached(priority: .utility) { [interval, maxDuration, action] in
                let deadline = ContinuousClock.now + maxDuration
                while !Task.isCancelled, ContinuousClock.now < deadline {
                    action()
                    do { try await Task.sleep(for: interval) } catch { return }
                }
            }
        }
    }

    /// Stops the loop. Safe to call when it isn't running.
    public func stop() {
        task.withLock { task in
            task?.cancel()
            task = nil
        }
    }
}
