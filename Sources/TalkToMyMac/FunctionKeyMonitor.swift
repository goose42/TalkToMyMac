import AppKit
import CoreGraphics
import OSLog
import TalkToMyMacCore

/// Handles shortcuts involving Fn/🌐, which Carbon's `RegisterEventHotKey` can't express:
/// it has no Fn modifier and can't bind a bare modifier key at all.
///
/// Uses an *active* `CGEventTap`, so it can also consume the key half of an Fn combo
/// (otherwise Fn+Space would type a space into the focused app). Active keyboard taps
/// require Accessibility permission — the same one auto-paste already needs.
///
/// Fn is also a real modifier (Fn+Delete, Fn+←, Fn+F-keys), so a hold press is reported
/// as interrupted if another key goes down while Fn is held, or if Fn is only tapped.
@MainActor
final class FunctionKeyMonitor {
    /// Fn-alone push-to-talk shortcut, if the hold slot uses Fn.
    var holdShortcut: GlobalShortcut?
    /// Fn+key toggle shortcut, if the toggle slot uses Fn.
    var toggleShortcut: GlobalShortcut?
    var onEvent: ((ShortcutEvent) -> Void)?

    /// Shorter Fn presses count as a tap, not push-to-talk, and are discarded.
    static let minimumHoldDuration: TimeInterval = 0.3

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnDown = false
    private var fnDownAt: TimeInterval = 0
    /// Set once Fn has been combined with another key, so its release isn't a PTT stop.
    private var fnUsedAsModifier = false
    /// Key codes whose key-down we consumed, so the matching key-up is consumed too.
    private var swallowedKeyUps: Set<Int64> = []
    private let logger = Logger(subsystem: "com.talktomymac.dictate", category: "FunctionKeyMonitor")

    var isRunning: Bool { tap != nil }

    /// Creates the event tap. Returns false if it couldn't be created — in practice,
    /// because Accessibility permission hasn't been granted yet.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                // Installed on the main run loop, so the callback runs on the main thread.
                let pass = MainActor.assumeIsolated {
                    let monitor = Unmanaged<FunctionKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                    return monitor.shouldPass(type: type, event: event)
                }
                return pass ? Unmanaged.passUnretained(event) : nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Could not create event tap — Accessibility permission missing?")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        fnDown = false
        swallowedKeyUps.removeAll()
    }

    /// Returns false to consume the event so the focused app never sees it.
    private func shouldPass(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system disables a tap that's slow or when secure input starts; re-arm it.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true

        case .flagsChanged:
            let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == GlobalShortcut.functionKeyCode {
                handleFunctionKey(isDown: event.flags.contains(.maskSecondaryFn))
            }
            // Never consume modifier changes — other apps must keep seeing correct state.
            return true

        case .keyDown:
            return handleKeyDown(event)

        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if swallowedKeyUps.remove(keyCode) != nil { return false }
            return true

        default:
            return true
        }
    }

    private func handleFunctionKey(isDown: Bool) {
        if isDown, !fnDown {
            fnDown = true
            fnDownAt = ProcessInfo.processInfo.systemUptime
            fnUsedAsModifier = false
            if holdShortcut != nil { onEvent?(.holdPressed) }
        } else if !isDown, fnDown {
            fnDown = false
            guard holdShortcut != nil else { return }
            let heldFor = ProcessInfo.processInfo.systemUptime - fnDownAt
            if fnUsedAsModifier || heldFor < Self.minimumHoldDuration {
                onEvent?(.holdInterrupted)
            } else {
                onEvent?(.holdReleased)
            }
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        // Track physical Fn state from flagsChanged rather than trusting the Fn flag on the
        // key event: arrows, F-keys, Home/End etc. carry that flag without Fn being held.
        guard fnDown else { return true }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if let toggle = toggleShortcut, toggle.modifiers.contains(.function),
           UInt32(keyCode) == toggle.keyCode,
           Self.carbonModifiers(of: event.flags) == toggle.modifiers.carbonOnly {
            swallowedKeyUps.insert(keyCode)
            fnUsedAsModifier = true
            // Ignore auto-repeat so holding Fn+Space doesn't flip the recording on and off.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                onEvent?(.togglePressed)
            }
            return false // consume: don't type the space
        }

        // Fn used as a modifier for something else: not a push-to-talk press after all.
        if !fnUsedAsModifier {
            fnUsedAsModifier = true
            if holdShortcut != nil { onEvent?(.holdInterrupted) }
        }
        return true
    }

    private static func carbonModifiers(of flags: CGEventFlags) -> GlobalShortcut.Modifiers {
        var m: GlobalShortcut.Modifiers = []
        if flags.contains(.maskCommand)   { m.insert(.command) }
        if flags.contains(.maskShift)     { m.insert(.shift) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl)   { m.insert(.control) }
        return m
    }
}
