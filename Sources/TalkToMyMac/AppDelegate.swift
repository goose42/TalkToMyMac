import AppKit
import AVFoundation
import FoundationModels
import OSLog
import TalkToMyMacCore

// MARK: - AppDelegate

@available(macOS 26.0, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, RecordingIndicator, PermissionChecking {

    // -- UI --
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var toggleMenuItem: NSMenuItem!
    /// Polls for Accessibility being granted, since that happens out-of-process in
    /// System Settings and there's no notification for it.
    private var accessibilityWatchTimer: Timer?
    private var hasShownAccessibilityAlert = false
    private let logger = Logger(subsystem: "com.talktomymac.dictate", category: "AppDelegate")

    // -- Core --
    private var controller: RecorderController!
    private let audioCapture = AudioCapture()
    private let speechService = SpeechTranscriptionService()
    private let formattingSettings = FormattingSettings()
    private var formatter: FoundationModelFormatter!
    private var pasteDelivery: PasteDelivery!
    private let shortcuts = ShortcutManager()
    private var settingsController: SettingsWindowController!
    private let transcriptionStore = TranscriptionStore()
    private var floatingIndicator: FloatingIndicatorController!

    // MARK: NSApplicationDelegate

    // Prevent App Nap from suspending this background-only app.
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the app alive — LSUIElement apps are aggressively napped/terminated.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Status bar dictation app must remain responsive"
        )

        formatter = FoundationModelFormatter(settings: formattingSettings)
        pasteDelivery = PasteDelivery(settings: formattingSettings)

        // Always-on-top dot that becomes a live waveform while recording.
        floatingIndicator = FloatingIndicatorController()
        let indicatorModel = floatingIndicator.model
        audioCapture.onLevels = { levels in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { indicatorModel.push(levels) }
            }
        }

        settingsController = SettingsWindowController(
            speechService: speechService,
            formatter: formatter,
            settings: formattingSettings,
            shortcuts: shortcuts,
            transcriptionStore: transcriptionStore,
            floatingIndicator: floatingIndicator
        )

        // Build the RecorderController: mic → Speech (on-device) → Foundation Models → paste.
        controller = RecorderController(
            recorder: audioCapture,
            permissionChecker: self,
            indicator: self,
            transcriber: speechService,
            formatter: formatter,
            outputSink: pasteDelivery
        )

        // Status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "mic", accessibilityDescription: "TalkToMyMac") {
                button.image = img
            } else {
                // SF Symbol unavailable — use a text fallback so the item is visible.
                button.title = "🎤"
            }
        }

        buildMenu()
        statusItem.menu = menu

        // Global shortcuts: push-to-talk (hold) and start/stop (toggle).
        shortcuts.onEvent = { [weak self] event in
            self?.handleShortcut(event)
        }
        shortcuts.start()

        // Surface a skipped paste instead of failing silently — the user has no other way
        // to tell the difference between "permission missing" and "the app is broken".
        // `PasteDelivery.skip` already hops to the main queue before invoking this.
        pasteDelivery.onSkip = { [weak self] reason in
            MainActor.assumeIsolated { self?.handlePasteSkipped(reason) }
        }

        // Speech recognition runs fully on-device and needs no authorization prompt, but the
        // model asset may need to be resolved/downloaded on first launch.
        Task { [weak self] in
            await self?.speechService.prepare()
        }

        requestPermissionsAtLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityWatchTimer?.invalidate()
    }

    // MARK: Permissions (requested up front, not on first use)

    /// Asks for everything the app needs at launch so the user is never surprised
    /// mid-dictation. The two system prompts are chained rather than fired together —
    /// stacking two modal permission dialogs at once is hostile.
    private func requestPermissionsAtLaunch() {
        // Logged unconditionally so permission state is diagnosable from Console.app
        // without needing to reproduce a failed dictation:
        //   log stream --predicate 'subsystem == "com.talktomymac.dictate"'
        logger.notice("""
            Launch permissions — mic: \(self.micPermissionLabel(), privacy: .public), \
            accessibility: \(PasteDelivery.isAccessibilityTrusted ? "granted" : "NOT granted", privacy: .public), \
            autoPasteEnabled: \(self.formattingSettings.autoPasteEnabled, privacy: .public)
            """)

        if micPermission() == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.requestAccessibilityIfNeeded()
                }
            }
        } else {
            requestAccessibilityIfNeeded()
        }
        startAccessibilityWatch()
    }

    /// Prompts for Accessibility only when auto-paste is actually enabled and we don't
    /// already have it — re-prompting when already trusted would nag on every launch.
    private func requestAccessibilityIfNeeded() {
        guard formattingSettings.autoPasteEnabled, !PasteDelivery.isAccessibilityTrusted else { return }
        // Shows the system's "open System Settings" dialog.
        PasteDelivery.requestAccessibilityPermission()
    }

    /// Accessibility is granted out-of-process, with no notification to observe, so poll.
    private func startAccessibilityWatch() {
        accessibilityWatchTimer?.invalidate()
        accessibilityWatchTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if PasteDelivery.isAccessibilityTrusted {
                    // Fn shortcuts use an event tap that can't exist before this point.
                    self.shortcuts.retryFailedRegistrations()
                    self.accessibilityWatchTimer?.invalidate()
                    self.accessibilityWatchTimer = nil
                }
            }
        }
    }

    private func handlePasteSkipped(_ reason: PasteDelivery.SkipReason) {
        // Only the missing-permission case is worth interrupting the user about; the others
        // are either intentional (toggle off) or self-evident.
        guard case .accessibilityNotTrusted = reason else { return }
        // Once per launch — Settings → General carries the status from then on, and an alert
        // on every dictation would be worse than the original silence.
        guard !hasShownAccessibilityAlert else { return }
        hasShownAccessibilityAlert = true
        let alert = NSAlert()
        alert.messageText = "Can't Paste at Cursor"
        alert.informativeText = """
            TalkToMyMac needs Accessibility access to paste text into other apps. \
            Your transcript was saved and is available in Settings → Transcriptions.

            Enable TalkToMyMac in System Settings → Privacy & Security → Accessibility, \
            then relaunch the app.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        // As an accessory (LSUIElement) app we're never active, so a modal alert can come
        // up behind the frontmost window unless we activate first.
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            PasteDelivery.openAccessibilitySettings()
        }
    }

    // MARK: Menu

    private func buildMenu() {
        menu = NSMenu()

        toggleMenuItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    @objc private func toggleRecording() {
        // The menu item behaves exactly like the toggle shortcut.
        handleShortcut(.togglePressed)
    }

    // MARK: Shortcuts

    private func handleShortcut(_ event: ShortcutEvent) {
        switch controller.handle(event) {
        case .started(let mode):
            toggleMenuItem.title = "Stop Recording"
            shortcuts.setEscapeActive(true)
            logger.info("Recording started (\(mode == .hold ? "hold" : "toggle", privacy: .public))")
        case .stopped:
            recordingEnded()
            processLastRecording()
        case .discarded:
            recordingEnded()
            audioCapture.discardLastRecording()
            logger.info("Recording discarded")
        case .latched:
            // Push-to-talk became toggle (e.g. Fn held, then Space): keeps recording until
            // the toggle shortcut is pressed again. Esc is already bound.
            logger.info("Hold recording latched into toggle mode")
        case .ignored:
            break
        case .failed(.permissionDenied):
            showPermissionDeniedAlert()
        case .failed(.permissionNotDetermined):
            break // permission request was triggered; user will retry
        case .failed(.recordingFailed(let msg)):
            logger.error("Recording failed: \(msg, privacy: .public)")
        }
    }

    private func recordingEnded() {
        toggleMenuItem.title = "Start Recording"
        shortcuts.setEscapeActive(false)
    }

    // MARK: Post-recording pipeline

    private func processLastRecording() {
        guard let rawSamples = audioCapture.lastRecordingRawSamples else {
            print("[Pipeline] No in-memory samples available")
            return
        }
        let sampleRate = audioCapture.lastRecordingSampleRate
        let duration = Double(rawSamples.count) / sampleRate
        print("[Pipeline] Raw capture: \(rawSamples.count) samples, sampleRate=\(sampleRate), duration=\(String(format: "%.2f", duration))s")

        Task { [weak self] in
            guard let self else { return }
            if let result = await self.controller.processRecording(samples: rawSamples, sampleRate: sampleRate) {
                print("[Pipeline] Transcript: \(result.finalText)")
                self.transcriptionStore.insert(result, audioSeconds: duration)
            } else {
                print("[Pipeline] Transcription returned nil (model not ready or empty result)")
            }
        }
    }

    // MARK: RecordingIndicator
    //
    // `RecordingIndicator`/`PermissionChecking` are plain (non-actor-isolated) protocols in
    // TalkToMyMacCore, called synchronously from `RecorderController`. These four
    // conformance methods are marked `nonisolated` so they can satisfy that synchronous,
    // isolation-agnostic contract; each hops to the main actor itself via
    // `DispatchQueue.main.async` before touching any UI state.

    nonisolated func setRecording(_ recording: Bool) {
        DispatchQueue.main.async { [weak self] in
            if let indicator = self?.floatingIndicator {
                if recording {
                    indicator.moveToActiveScreen()
                    indicator.model.resetLevels()
                }
                indicator.model.phase = recording ? .recording : .idle
            }
            guard let button = self?.statusItem.button else { return }
            if recording {
                let img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
                button.image = img
                button.contentTintColor = .systemRed
            } else {
                let img = NSImage(systemSymbolName: "mic", accessibilityDescription: "TalkToMyMac")
                button.image = img
                button.contentTintColor = nil
            }
        }
    }

    nonisolated func setProcessing(_ processing: Bool) {
        DispatchQueue.main.async { [weak self] in
            if let model = self?.floatingIndicator?.model {
                if processing {
                    model.phase = .processing
                } else if model.phase == .processing {
                    // Don't clobber a new recording that started while this one was processing.
                    model.phase = .idle
                }
            }
            guard let button = self?.statusItem.button else { return }
            if processing {
                let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Processing")
                button.image = img
                button.contentTintColor = .systemOrange
            } else {
                let img = NSImage(systemSymbolName: "mic", accessibilityDescription: "TalkToMyMac")
                button.image = img
                button.contentTintColor = nil
            }
        }
    }

    // MARK: PermissionChecking

    nonisolated func micPermission() -> MicPermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:            return .authorized
        case .denied, .restricted:   return .denied
        case .notDetermined:         return .notDetermined
        @unknown default:            return .notDetermined
        }
    }

    nonisolated func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    @objc private func openSettings() {
        settingsController.showWindow()
    }

    // MARK: Helpers

    private func micPermissionLabel() -> String {
        switch micPermission() {
        case .authorized:      return "Authorized"
        case .denied:          return "Denied"
        case .notDetermined:   return "Not Determined"
        }
    }

    private func showPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Access Denied"
        alert.informativeText = "TalkToMyMac needs microphone access to record audio. Please grant permission in System Settings → Privacy & Security → Microphone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
