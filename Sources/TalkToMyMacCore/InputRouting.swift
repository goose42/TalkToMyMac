/// Decisions about which microphone to record from.
public enum InputRouting {
    /// The UID of the microphone to record from, or nil to use the system default.
    ///
    /// With `builtInOnly` it's always the Mac's own microphone (`builtInUID`), whatever is
    /// selected or connected, and `connected` is never called: that read is what touches
    /// every audio device, Bluetooth ones included. Otherwise it's the selection, if connected.
    public static func targetUID(selection: InputDeviceSelection, builtInOnly: Bool, builtInUID: String?,
                          connected: () -> [String]) -> String? {
        if builtInOnly { return builtInUID }
        return selection.deviceUID(connected: connected())
    }
}
