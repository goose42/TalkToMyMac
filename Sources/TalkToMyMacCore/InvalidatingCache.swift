import Synchronization

/// A lazily computed value that's kept until `invalidate()` — e.g. the list of audio input
/// devices, which is expensive to read from CoreAudio (one round trip per device, slow while
/// a Bluetooth device is changing profile) but only changes when CoreAudio says so.
public final class InvalidatingCache<Value: Sendable>: Sendable {
    private let compute: @Sendable () -> Value
    private let stored = Mutex<Value?>(nil)

    public init(compute: @escaping @Sendable () -> Value) {
        self.compute = compute
    }

    /// The cached value, computing it first if there isn't one.
    public var value: Value {
        stored.withLock { stored in
            if let stored { return stored }
            let fresh = compute()
            stored = fresh
            return fresh
        }
    }

    /// Drops the cached value so the next read recomputes it.
    public func invalidate() {
        stored.withLock { $0 = nil }
    }
}
