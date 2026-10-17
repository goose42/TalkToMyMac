import Foundation
import Synchronization

/// Runs `operation`, giving up after `timeout`: returns its result if it finishes in time,
/// or nil if it doesn't, in which case it is cancelled.
///
/// Unlike racing in a task group, this returns as soon as the deadline passes even if
/// `operation` ignores cancellation (as on-device model calls may), rather than waiting for
/// it to wind down.
public func withDeadline<T: Sendable>(_ timeout: Duration,
                                      operation: @escaping @Sendable () async -> T) async -> T? {
    let finish = Once<T?>()
    let work = Task { finish(await operation()) }
    let timer = Task {
        try? await Task.sleep(for: timeout)
        finish(nil)
    }
    let result = await finish.value
    work.cancel()
    timer.cancel()
    return result
}

/// The time limit on LLM formatting, whichever model runs it. Past it, the transcript is
/// delivered unformatted.
public enum FormattingDeadline {
    public static let timeout: Duration = .seconds(4)
}

/// A value that's set once, by whichever caller gets there first, and awaited.
private final class Once<T: Sendable>: Sendable {
    private enum State {
        case waiting(CheckedContinuation<T, Never>?)
        case done(T)
    }
    private let state = Mutex<State>(.waiting(nil))

    /// Sets the value; later calls are ignored.
    func callAsFunction(_ value: T) {
        let continuation: CheckedContinuation<T, Never>? = state.withLock { state in
            guard case .waiting(let continuation) = state else { return nil }
            state = .done(value)
            return continuation
        }
        continuation?.resume(returning: value)
    }

    /// Waits for the value. Only one caller may wait.
    var value: T {
        get async {
            await withCheckedContinuation { continuation in
                let ready: T? = state.withLock { state in
                    switch state {
                    case .done(let value):
                        return value
                    case .waiting:
                        state = .waiting(continuation)
                        return nil
                    }
                }
                if let ready { continuation.resume(returning: ready) }
            }
        }
    }
}
