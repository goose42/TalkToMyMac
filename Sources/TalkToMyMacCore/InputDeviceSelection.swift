/// Which microphone recordings come from: whatever the Mac is set to use, or one chosen device
/// by CoreAudio UID, so connecting a Bluetooth headset doesn't swap in its weaker mic.
public enum InputDeviceSelection: Hashable, Sendable {
    case systemDefault
    case device(uid: String)

    /// Restores a selection saved as `persistedUID`; nil or empty means the system default.
    public init(persistedUID: String?) {
        if let uid = persistedUID, !uid.isEmpty {
            self = .device(uid: uid)
        } else {
            self = .systemDefault
        }
    }

    public var persistedUID: String? {
        switch self {
        case .systemDefault:    return nil
        case .device(let uid):  return uid
        }
    }

    /// The UID of the device to record from, or nil to use the system default — also when the
    /// chosen device isn't among the `connected` input devices, so dictation still works.
    public func deviceUID(connected: [String]) -> String? {
        guard case .device(let uid) = self, connected.contains(uid) else { return nil }
        return uid
    }
}
