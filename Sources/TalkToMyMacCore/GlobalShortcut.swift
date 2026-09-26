/// A global keyboard shortcut: a virtual key code plus modifiers.
///
/// Modifier bits deliberately use Carbon's values (`cmdKey`, `shiftKey`, …) so the struct
/// can be handed straight to `RegisterEventHotKey` without this module importing Carbon.
public struct GlobalShortcut: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 8)   // cmdKey
        public static let shift   = Modifiers(rawValue: 1 << 9)   // shiftKey
        public static let option  = Modifiers(rawValue: 1 << 11)  // optionKey
        public static let control = Modifiers(rawValue: 1 << 12)  // controlKey
        /// Fn/🌐. Mirrors Carbon's `kEventKeyModifierFnMask`, but `RegisterEventHotKey`
        /// ignores it — shortcuts using Fn are handled by an event tap instead.
        public static let function = Modifiers(rawValue: 1 << 17)

        /// The modifiers Carbon hotkeys understand.
        public var carbonOnly: Modifiers { subtracting(.function) }
    }

    /// Virtual key code (`kVK_*`).
    public var keyCode: UInt32
    public var modifiers: Modifiers
    /// Human-readable key name captured when the shortcut was recorded, since turning a
    /// key code back into a character depends on the active keyboard layout.
    public var keyLabel: String

    public init(keyCode: UInt32, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// E.g. "⌃⇧Space" or "Fn+Space", in the standard macOS modifier order.
    public var displayString: String {
        if isFunctionKeyAlone { return "Fn" }
        var s = modifiers.contains(.function) ? "Fn+" : ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + keyLabel
    }

    // MARK: Key codes

    public static let escapeKeyCode: UInt32 = 53  // kVK_Escape
    public static let spaceKeyCode: UInt32 = 49   // kVK_Space
    public static let functionKeyCode: UInt32 = 63 // kVK_Function (Fn/🌐)

    /// Fn pressed and released on its own — a modifier-only shortcut.
    public var isFunctionKeyAlone: Bool { keyCode == Self.functionKeyCode }

    /// True if this needs the event-tap backend rather than a Carbon hotkey.
    public var usesFunctionKey: Bool { isFunctionKeyAlone || modifiers.contains(.function) }

    /// Keys whose events carry the Fn flag on their own (arrows, F-keys, Home/End, …),
    /// so the flag alone can't be taken to mean Fn was physically held.
    public static let inherentlyFunctionFlaggedKeyCodes: Set<UInt32> =
        functionKeyCodes.union([115, 116, 117, 119, 121, 123, 124, 125, 126, 114])

    /// F1–F20. These are safe to bind without modifiers since they rarely type anything.
    static let functionKeyCodes: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,  // F1–F12
        105, 107, 113, 106, 64, 79, 80, 90,                       // F13–F20
    ]

    /// Key names for keys whose `charactersIgnoringModifiers` is unprintable or blank.
    public static func specialKeyLabel(for keyCode: UInt32) -> String? {
        switch keyCode {
        case 49:  return "Space"
        case 36:  return "↩"
        case 48:  return "⇥"
        case 51:  return "⌫"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "PgUp"
        case 121: return "PgDn"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64:  return "F17"
        case 79:  return "F18"
        case 80:  return "F19"
        case 90:  return "F20"
        default:  return nil
        }
    }

    // MARK: Defaults

    /// Hold Fn to talk.
    public static let defaultHold = GlobalShortcut(
        keyCode: functionKeyCode, modifiers: [], keyLabel: "Fn"
    )

    /// Fn+Space to start/stop. Pressing it mid-hold latches the hold recording.
    public static let defaultToggle = GlobalShortcut(
        keyCode: spaceKeyCode, modifiers: [.function], keyLabel: "Space"
    )

    // MARK: Validation

    public enum ValidationError: Error, Equatable {
        case escapeReserved
        case needsModifier
        case duplicate
        case functionAloneOnlyForHold

        public var message: String {
            switch self {
            case .escapeReserved: return "Esc is reserved for discarding a recording."
            case .needsModifier:  return "Add a modifier (⌃ ⌥ ⇧ ⌘) — a bare key would hijack normal typing."
            case .duplicate:      return "That's already used by the other shortcut."
            case .functionAloneOnlyForHold:
                return "Fn by itself only works for push to talk — for toggle, combine it with a key."
            }
        }
    }

    /// Checks `self` is usable as a global shortcut alongside `other`. `forHold` is true for
    /// the push-to-talk slot.
    public func validate(against other: GlobalShortcut?, forHold: Bool = false) -> ValidationError? {
        if keyCode == Self.escapeKeyCode { return .escapeReserved }
        if isFunctionKeyAlone {
            // As a toggle, every Fn+Delete / Fn+← would start or stop a recording.
            if !forHold { return .functionAloneOnlyForHold }
            if let other, other.isFunctionKeyAlone { return .duplicate }
            return nil
        }
        // A global hotkey swallows the keystroke system-wide, so binding a bare letter
        // would make that letter untypeable in every app.
        if modifiers.isEmpty && !Self.functionKeyCodes.contains(keyCode) { return .needsModifier }
        if let other, other.keyCode == keyCode, other.modifiers == modifiers { return .duplicate }
        return nil
    }
}
