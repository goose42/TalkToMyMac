import AppKit
import SwiftUI
import TalkToMyMacCore

/// A click-to-record shortcut field: click it, press the new combination, done.
/// Esc cancels without changing anything.
///
/// Uses a *local* `NSEvent` monitor, which only sees keystrokes sent to this app's own
/// windows and so needs no extra permissions.
struct ShortcutRecorderView: View {
    let shortcut: GlobalShortcut
    /// Registration problem reported by `ShortcutManager`.
    let registrationError: String?
    /// Called when listening starts/stops, so global hotkeys can be released meanwhile —
    /// otherwise pressing the current combo would trigger it instead of being captured.
    let onListeningChanged: (Bool) -> Void
    /// Applies the captured shortcut; returns an error message if it was rejected.
    let onCapture: (GlobalShortcut) -> String?

    @State private var isListening = false
    @State private var monitor: Any?
    @State private var captureError: String?
    /// Fn physically held during listening (tracked from flagsChanged, since arrows and
    /// F-keys carry the Fn flag on their own).
    @State private var fnHeld = false
    @State private var keyPressedDuringFn = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: toggleListening) {
                Text(isListening ? "Press shortcut…" : shortcut.displayString)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
            .tint(isListening ? .accentColor : nil)
            .help(isListening ? "Press a key combination, or Esc to cancel" : "Click to change")

            if let message = captureError ?? registrationError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear(perform: stopListening)
    }

    private func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    private func startListening() {
        captureError = nil
        isListening = true
        onListeningChanged(true)
        fnHeld = false
        keyPressedDuringFn = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                handleFlagsChanged(event)
                return event
            }
            handle(event)
            return nil // swallow it so it doesn't also act on the Settings UI
        }
    }

    private func stopListening() {
        guard isListening else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isListening = false
        onListeningChanged(false)
    }

    /// Fn pressed and released with no other key in between records "Fn" on its own.
    private func handleFlagsChanged(_ event: NSEvent) {
        guard UInt32(event.keyCode) == GlobalShortcut.functionKeyCode else { return }
        if event.modifierFlags.contains(.function) {
            fnHeld = true
            keyPressedDuringFn = false
        } else if fnHeld {
            fnHeld = false
            guard !keyPressedDuringFn else { return }
            stopListening()
            captureError = onCapture(GlobalShortcut(
                keyCode: GlobalShortcut.functionKeyCode, modifiers: [], keyLabel: "Fn"))
        }
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        if keyCode == GlobalShortcut.escapeKeyCode {
            stopListening()
            return
        }

        var modifiers = Self.carbonModifiers(from: event.modifierFlags)
        if fnHeld && !GlobalShortcut.inherentlyFunctionFlaggedKeyCodes.contains(keyCode) {
            modifiers.insert(.function)
            keyPressedDuringFn = true
        }
        let captured = GlobalShortcut(keyCode: keyCode, modifiers: modifiers, keyLabel: Self.label(for: event))
        // Restore global hotkeys *before* applying, so the new one is actually registered
        // (and any registration failure reported) as part of applying it.
        stopListening()
        captureError = onCapture(captured)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> GlobalShortcut.Modifiers {
        var m: GlobalShortcut.Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift)   { m.insert(.shift) }
        if flags.contains(.option)  { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        return m
    }

    private static func label(for event: NSEvent) -> String {
        if let special = GlobalShortcut.specialKeyLabel(for: UInt32(event.keyCode)) {
            return special
        }
        // Unmodified character, so ⇧1 is labelled "1" (displayed as ⇧1) rather than "!",
        // and ⌥-letter combos show the letter rather than the ⌥ glyph.
        let raw = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? "?"
        return raw.uppercased()
    }
}
