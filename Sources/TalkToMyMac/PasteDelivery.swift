import AppKit
import ApplicationServices
import CoreGraphics
import OSLog
import TalkToMyMacCore

/// Delivers formatted text to whatever app is under the cursor by staging it on the
/// clipboard and synthesizing ⌘V, then restoring whatever was on the clipboard before.
///
/// Requires Accessibility permission (`AXIsProcessTrusted`) — without it, `CGEvent.post`
/// is silently dropped by the system, so delivery is skipped up front instead. The
/// transcript is never lost either way: it's already been written to `TranscriptionStore`
/// by the time this runs.
///
/// `@unchecked Sendable`: shared between the non-isolated `RecorderController` pipeline
/// (calls `deliver(text:)`) and holds a reference to `FormattingSettings`, which is itself
/// shared with the main-actor Settings UI. `deliver(text:)` explicitly hops to the main
/// thread for all of its actual work (see below), so there's no unsynchronized mutation.
final class PasteDelivery: OutputDelivering, @unchecked Sendable {
    /// Why a delivery attempt didn't paste. Reported through `onSkip` so the UI can
    /// surface it — a silent skip is indistinguishable from a broken app.
    enum SkipReason {
        case disabledInSettings
        case accessibilityNotTrusted
        case ourAppFrontmost
        case eventCreationFailed

        var message: String {
            switch self {
            case .disabledInSettings:      return "Auto-paste is turned off in Settings."
            case .accessibilityNotTrusted: return "Accessibility permission not granted — cannot paste."
            case .ourAppFrontmost:         return "TalkToMyMac is frontmost — nothing to paste into."
            case .eventCreationFailed:     return "Could not synthesize the ⌘V keystroke."
            }
        }
    }

    private let settings: FormattingSettings
    private let logger = Logger(subsystem: "com.talktomymac.dictate", category: "PasteDelivery")

    /// Called (on the main thread) when a paste was skipped, with the reason.
    var onSkip: (@Sendable (SkipReason) -> Void)?

    /// How long to wait before restoring the user's previous clipboard contents. Needs to
    /// outlast the target app's handling of the synthetic ⌘V, or we'd swap the text back
    /// out from under a slow paste.
    private static let restoreDelay: TimeInterval = 0.3

    init(settings: FormattingSettings) {
        self.settings = settings
    }

    /// True if the app is authorized for Accessibility (UI-scripting) access.
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts the user for Accessibility access if not already granted, showing the
    /// system's "open System Settings" dialog.
    ///
    /// Uses the raw key string instead of the `kAXTrustedCheckOptionPrompt` global: that
    /// global is an `Unmanaged<CFString>!` the SDK doesn't mark concurrency-safe. The
    /// literal is verified to match the constant's runtime value.
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options: [String: Any] = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Opens the Accessibility pane of System Settings directly.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func deliver(text: String) throws {
        guard settings.autoPasteEnabled else {
            skip(.disabledInSettings)
            return
        }
        guard Self.isAccessibilityTrusted else {
            skip(.accessibilityNotTrusted)
            return
        }

        // The protocol is synchronous, but pasteboard/CGEvent work belongs on the main
        // thread; hop there without assuming which thread we were called from.
        if Thread.isMainThread {
            performPaste(text: text)
        } else {
            DispatchQueue.main.sync { self.performPaste(text: text) }
        }
    }

    private func skip(_ reason: SkipReason) {
        logger.warning("Paste skipped: \(reason.message, privacy: .public)")
        let cb = onSkip
        DispatchQueue.main.async { cb?(reason) }
    }

    private func performPaste(text: String) {
        // Don't steal our own Settings window's paste if it happens to be frontmost.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            skip(.ourAppFrontmost)
            return
        }

        let pasteboard = NSPasteboard.general
        let savedText = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        guard postCommandV() else {
            skip(.eventCreationFailed)
            return
        }
        logger.info("Pasted \(text.count, privacy: .public) characters")

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay) { [logger] in
            // Only restore if nothing else touched the clipboard since our paste — otherwise
            // we'd clobber something the user copied in the interim.
            guard pasteboard.changeCount == ourChangeCount else {
                logger.info("Clipboard changed since paste — leaving it alone")
                return
            }
            pasteboard.clearContents()
            if let savedText {
                pasteboard.setString(savedText, forType: .string)
            }
        }
    }

    private func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("Could not create CGEventSource")
            return false
        }
        let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            logger.error("Could not create CGEvents for ⌘V")
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
