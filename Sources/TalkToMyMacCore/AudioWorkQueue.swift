import Foundation

/// A serial queue for CoreAudio work (opening devices, starting engines, setting volume),
/// which can block for seconds while a Bluetooth headset switches profile. Callers on the
/// main thread — notably the Fn-key event tap, which macOS disables if it's slow — hand the
/// work over with `async` and return at once; jobs run one at a time, in submission order.
public final class AudioWorkQueue: Sendable {
    private let queue: DispatchQueue

    public init(label: String) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    /// Runs `work` after everything already submitted, without waiting for it.
    public func async(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// Runs `work` after everything already submitted and returns its result. Blocks the
    /// caller, so use it only where the result is needed (e.g. restoring volume on quit).
    public func sync<T>(_ work: () -> T) -> T {
        queue.sync(execute: work)
    }

    /// Suspends until everything submitted so far has finished.
    public func drain() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}
