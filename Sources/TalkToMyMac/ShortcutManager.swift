import Carbon
import Foundation
import Observation
import OSLog
import TalkToMyMacCore

/// Owns the two user-configurable dictation shortcuts (push-to-talk and toggle), persists
/// them, keeps them registered as global hotkeys, and turns key presses into
/// `ShortcutEvent`s for `RecorderController`.
@MainActor
@Observable
final class ShortcutManager {
    enum Slot {
        case hold
        case toggle
    }

    private(set) var holdShortcut: GlobalShortcut
    private(set) var toggleShortcut: GlobalShortcut

    /// Why a shortcut couldn't be registered, shown next to it in Settings.
    ///
    /// Note this can't catch a clash with *another app's* shortcut: Carbon only reports
    /// `eventHotKeyExistsErr` for a duplicate within this process, and macOS offers no API
    /// to enumerate other apps' global shortcuts (verified empirically).
    private(set) var holdError: String?
    private(set) var toggleError: String?

    /// Receives every shortcut event, on the main actor.
    @ObservationIgnored var onEvent: ((ShortcutEvent) -> Void)?

    @ObservationIgnored private let hotkeys = HotkeyCenter()
    /// Backend for shortcuts involving Fn, which Carbon hotkeys can't express.
    @ObservationIgnored private let fnMonitor = FunctionKeyMonitor()
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var escapeActive = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.talktomymac.dictate", category: "Shortcuts")

    private enum HotkeyID {
        static let hold: UInt32 = 1
        static let toggle: UInt32 = 2
        static let escape: UInt32 = 3
    }

    private enum Keys {
        static let hold = "holdShortcut"
        static let toggle = "toggleShortcut"
    }

    init() {
        holdShortcut = Self.load(Keys.hold) ?? .defaultHold
        toggleShortcut = Self.load(Keys.toggle) ?? .defaultToggle
        fnMonitor.onEvent = { [weak self] in self?.onEvent?($0) }
    }

    /// Registers the saved shortcuts. Call once at launch.
    func start() {
        registerSlot(.hold)
        registerSlot(.toggle)
    }

    /// Retries any shortcut that failed to register — call when Accessibility is granted,
    /// since Fn shortcuts can't be installed until then.
    func retryFailedRegistrations() {
        guard !isSuspended else { return }
        if holdError != nil { registerSlot(.hold) }
        if toggleError != nil { registerSlot(.toggle) }
    }

    /// Validates, registers, and persists a new shortcut for `slot`. On failure the
    /// previous shortcut stays in place and the returned message explains why.
    @discardableResult
    func update(_ slot: Slot, to shortcut: GlobalShortcut) -> String? {
        let other = (slot == .hold) ? toggleShortcut : holdShortcut
        if let error = shortcut.validate(against: other, forHold: slot == .hold) {
            return error.message
        }

        let previous = (slot == .hold) ? holdShortcut : toggleShortcut
        setShortcut(shortcut, for: slot)
        if !isSuspended, let message = registerSlot(slot) {
            // Registration failed — put the old one back rather than leave nothing bound.
            setShortcut(previous, for: slot)
            registerSlot(slot)
            return message
        }
        save(shortcut, key: slot == .hold ? Keys.hold : Keys.toggle)
        return nil
    }

    /// Temporarily releases every hotkey. Used while the Settings shortcut recorder is
    /// listening: a registered global hotkey is consumed before the Settings window ever
    /// sees it, so without this, re-pressing the current combo to re-bind it would start
    /// a recording instead.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        hotkeys.unregisterAll()
        fnMonitor.stop()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        registerSlot(.hold)
        registerSlot(.toggle)
        if escapeActive { registerEscape() }
    }

    /// Binds Esc (to discard) only while a recording is in progress. Registering it
    /// permanently would steal Escape from every other app on the system.
    func setEscapeActive(_ active: Bool) {
        escapeActive = active
        if active {
            if !isSuspended { registerEscape() }
        } else {
            hotkeys.unregister(id: HotkeyID.escape)
        }
    }

    // MARK: - Private

    @discardableResult
    private func registerSlot(_ slot: Slot) -> String? {
        let shortcut = (slot == .hold) ? holdShortcut : toggleShortcut
        let message = shortcut.usesFunctionKey ? registerWithFnMonitor(slot) : registerWithCarbon(slot)
        switch slot {
        case .hold:   holdError = message
        case .toggle: toggleError = message
        }
        if let message {
            logger.error("Could not register \(shortcut.displayString, privacy: .public): \(message, privacy: .public)")
        }
        return message
    }

    /// Fn shortcuts go through the event tap; the slot's Carbon hotkey is removed.
    private func registerWithFnMonitor(_ slot: Slot) -> String? {
        switch slot {
        case .hold:
            hotkeys.unregister(id: HotkeyID.hold)
            fnMonitor.holdShortcut = holdShortcut
        case .toggle:
            hotkeys.unregister(id: HotkeyID.toggle)
            fnMonitor.toggleShortcut = toggleShortcut
        }
        return fnMonitor.start()
            ? nil
            : "Fn shortcuts need Accessibility permission (Privacy & Security → Accessibility)."
    }

    private func registerWithCarbon(_ slot: Slot) -> String? {
        // This slot no longer uses Fn: take it off the tap, and drop the tap if unused.
        switch slot {
        case .hold:   fnMonitor.holdShortcut = nil
        case .toggle: fnMonitor.toggleShortcut = nil
        }
        if fnMonitor.holdShortcut == nil && fnMonitor.toggleShortcut == nil { fnMonitor.stop() }

        let status: OSStatus
        switch slot {
        case .hold:
            status = hotkeys.register(
                id: HotkeyID.hold,
                shortcut: holdShortcut,
                onPress: { [weak self] in self?.onEvent?(.holdPressed) },
                onRelease: { [weak self] in self?.onEvent?(.holdReleased) }
            )
        case .toggle:
            status = hotkeys.register(
                id: HotkeyID.toggle,
                shortcut: toggleShortcut,
                onPress: { [weak self] in self?.onEvent?(.togglePressed) }
            )
        }

        return (status == noErr) ? nil : Self.describe(status)
    }

    private func registerEscape() {
        let esc = GlobalShortcut(keyCode: GlobalShortcut.escapeKeyCode, modifiers: [], keyLabel: "Esc")
        let status = hotkeys.register(id: HotkeyID.escape, shortcut: esc,
                                      onPress: { [weak self] in self?.onEvent?(.cancel) })
        if status != noErr {
            logger.error("Could not register Esc for discard: \(Self.describe(status), privacy: .public)")
        }
    }

    private func setShortcut(_ shortcut: GlobalShortcut, for slot: Slot) {
        switch slot {
        case .hold:   holdShortcut = shortcut
        case .toggle: toggleShortcut = shortcut
        }
    }

    private static func describe(_ status: OSStatus) -> String {
        if status == OSStatus(eventHotKeyExistsErr) {
            return "This shortcut is already registered."
        }
        return "Couldn't register this shortcut (error \(status))."
    }

    private static func load(_ key: String) -> GlobalShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GlobalShortcut.self, from: data)
    }

    private func save(_ shortcut: GlobalShortcut, key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
