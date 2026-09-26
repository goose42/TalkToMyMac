import Carbon
import Foundation
import TalkToMyMacCore

/// Registers system-wide hotkeys via Carbon's `RegisterEventHotKey`, reporting both key
/// press and key release.
///
/// Carbon hotkeys need no Accessibility or Input Monitoring permission, and — unlike an
/// `NSEvent` global monitor — they deliver a distinct release event, which is what makes
/// push-to-talk possible. The trade-off is that a registered combination is consumed
/// system-wide, so other apps never see it while it's registered.
@MainActor
final class HotkeyCenter {
    struct Handlers {
        var onPress: () -> Void
        var onRelease: (() -> Void)?
    }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: Handlers] = [:]
    private var eventHandlerRef: EventHandlerRef?

    private static let signature = OSType(0x54544D4D) // "TTMM"

    init() {
        installEventHandler()
    }

    /// Registers `shortcut` under `id`, replacing anything previously registered there.
    /// Returns the Carbon status. `eventHotKeyExistsErr` only fires for a duplicate within
    /// this process — a combo already bound by another app registers without error.
    @discardableResult
    func register(id: UInt32, shortcut: GlobalShortcut, onPress: @escaping () -> Void,
                  onRelease: (() -> Void)? = nil) -> OSStatus {
        unregister(id: id)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers.rawValue,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return status }
        refs[id] = ref
        handlers[id] = Handlers(onPress: onPress, onRelease: onRelease)
        return noErr
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: id)
    }

    func unregisterAll() {
        for id in Array(refs.keys) { unregister(id: id) }
    }

    func isRegistered(id: UInt32) -> Bool { refs[id] != nil }

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotkeyCenter.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                let id = hotKeyID.id

                // Carbon delivers application-target events on the main thread.
                let handled = MainActor.assumeIsolated {
                    let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                    return center.dispatch(id: id, isPress: isPress)
                }
                // Returning noErr for a hotkey we don't own would tell Carbon it was handled
                // and stop it reaching any other installed handler (e.g. a second
                // HotkeyCenter), so pass unowned events along.
                return handled ? noErr : OSStatus(eventNotHandledErr)
            },
            eventTypes.count,
            &eventTypes,
            selfPtr,
            &eventHandlerRef
        )
    }

    /// Returns false if `id` isn't registered with this instance.
    private func dispatch(id: UInt32, isPress: Bool) -> Bool {
        guard let h = handlers[id] else { return false }
        if isPress { h.onPress() } else { h.onRelease?() }
        return true
    }
}
