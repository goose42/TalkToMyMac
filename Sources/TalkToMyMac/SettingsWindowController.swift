import AppKit
import AVFoundation
import SwiftUI
import TalkToMyMacCore

/// Manages the settings window. Call `showWindow()` to open or bring to front.
///
/// While the window is open the app switches to the `.regular` activation policy, so it gets a
/// Dock icon and a Cmd-Tab entry. As a menu-bar-only (`.accessory`) app, clicking another app
/// buries the window with no way back to it. Closing the window restores `.accessory`.
@available(macOS 26.0, *)
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let speechService: SpeechTranscriptionService
    private let parakeetService: ParakeetTranscriptionService
    private let transcriptionRouter: TranscriptionRouter
    private let formatter: FoundationModelFormatter
    private let groqFormatter: GroqFormatter
    private let openRouterFormatter: OpenRouterFormatter
    private let settings: FormattingSettings
    private let shortcuts: ShortcutManager
    private let transcriptionStore: TranscriptionStore
    private let floatingIndicator: FloatingIndicatorController
    private let dictionaryEditor: DictionaryEditor

    init(speechService: SpeechTranscriptionService, parakeetService: ParakeetTranscriptionService,
         transcriptionRouter: TranscriptionRouter,
         formatter: FoundationModelFormatter,
         groqFormatter: GroqFormatter, openRouterFormatter: OpenRouterFormatter,
         settings: FormattingSettings, shortcuts: ShortcutManager, transcriptionStore: TranscriptionStore,
         floatingIndicator: FloatingIndicatorController) {
        self.speechService = speechService
        self.parakeetService = parakeetService
        self.transcriptionRouter = transcriptionRouter
        self.formatter = formatter
        self.groqFormatter = groqFormatter
        self.openRouterFormatter = openRouterFormatter
        self.settings = settings
        self.shortcuts = shortcuts
        self.transcriptionStore = transcriptionStore
        self.floatingIndicator = floatingIndicator
        self.dictionaryEditor = DictionaryEditor(
            entries: settings.dictionaryEntries,
            generator: FoundationModelEntryGenerator()
        ) { [settings] entries in
            settings.dictionaryEntries = entries
        }
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = SettingsRootView(
            speechService: speechService, parakeetService: parakeetService,
            transcriptionRouter: transcriptionRouter, formatter: formatter,
            groqFormatter: groqFormatter, openRouterFormatter: openRouterFormatter,
            settings: settings, shortcuts: shortcuts,
            transcriptionStore: transcriptionStore, floatingIndicator: floatingIndicator,
            dictionaryEditor: dictionaryEditor
        )
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = []

        let win = NSWindow(contentViewController: controller)
        win.title = "Settings"
        // Full-size content plus an (empty) unified toolbar lets the sidebar run up under the
        // title bar, as in System Settings.
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.toolbar = NSToolbar()
        win.toolbarStyle = .unified
        win.setContentSize(Self.contentSize)
        win.contentMinSize = Self.contentMinSize
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private static let contentSize = NSSize(width: 980, height: 760)
    private static let contentMinSize = NSSize(width: 720, height: 480)
}

// MARK: - Sidebar

@available(macOS 26.0, *)
private struct SettingsRootView: View {
    let speechService: SpeechTranscriptionService
    let parakeetService: ParakeetTranscriptionService
    let transcriptionRouter: TranscriptionRouter
    let formatter: FoundationModelFormatter
    let groqFormatter: GroqFormatter
    let openRouterFormatter: OpenRouterFormatter
    let settings: FormattingSettings
    let shortcuts: ShortcutManager
    let transcriptionStore: TranscriptionStore
    let floatingIndicator: FloatingIndicatorController
    let dictionaryEditor: DictionaryEditor

    @State private var selection: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            // `id: \.self` tags each row with the pane itself, matching `selection`'s type.
            // Tagged by `SettingsPane.ID` (a String) instead, clicks never change the selection.
            List(SettingsPane.allCases, id: \.self, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            let pane = selection ?? .general
            detail(for: pane)
                .navigationTitle(pane.title)
        }
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            SettingsView(speechService: speechService, settings: settings,
                         shortcuts: shortcuts, floatingIndicator: floatingIndicator)
        case .audio:
            AudioSettingsView(settings: settings)
        case .dictionary:
            DictionaryView(editor: dictionaryEditor, settings: settings, transcriber: transcriptionRouter)
        case .formatting:
            FormattingView(formatter: formatter, settings: settings)
        case .models:
            ModelsView(groqFormatter: groqFormatter, openRouterFormatter: openRouterFormatter,
                       parakeetService: parakeetService, settings: settings)
        case .transcriptions:
            TranscriptionsView(store: transcriptionStore)
        case .instrumentation:
            InstrumentationView(store: transcriptionStore, settings: settings)
        case .storage:
            StorageView(store: transcriptionStore)
        }
    }
}

// MARK: - SwiftUI Settings View

@available(macOS 26.0, *)
private struct SettingsView: View {
    let speechService: SpeechTranscriptionService
    @Bindable var settings: FormattingSettings
    let shortcuts: ShortcutManager
    let floatingIndicator: FloatingIndicatorController

    // Both are granted out-of-process in System Settings with no notification to observe,
    // so they're polled while this tab is on screen.
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var accessibilityTrusted = PasteDelivery.isAccessibilityTrusted
    /// Mirrors `floatingIndicator.isVisible`, which isn't observable; Settings is the only
    /// place it changes.
    @State private var showFloatingIndicator: Bool

    init(speechService: SpeechTranscriptionService, settings: FormattingSettings,
         shortcuts: ShortcutManager, floatingIndicator: FloatingIndicatorController) {
        self.speechService = speechService
        self.settings = settings
        self.shortcuts = shortcuts
        self.floatingIndicator = floatingIndicator
        _showFloatingIndicator = State(initialValue: floatingIndicator.isVisible)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Push to talk (hold)") {
                    ShortcutRecorderView(
                        shortcut: shortcuts.holdShortcut,
                        registrationError: shortcuts.holdError,
                        onListeningChanged: setListening,
                        onCapture: { shortcuts.update(.hold, to: $0) }
                    )
                }
                LabeledContent("Start / stop (toggle)") {
                    ShortcutRecorderView(
                        shortcut: shortcuts.toggleShortcut,
                        registrationError: shortcuts.toggleError,
                        onListeningChanged: setListening,
                        onCapture: { shortcuts.update(.toggle, to: $0) }
                    )
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Hold the push-to-talk shortcut while speaking and release to transcribe. "
                     + "Or press the toggle shortcut once to start and again to stop — pressing it "
                     + "while holding push-to-talk keeps the recording going hands-free. "
                     + "Press Esc during either to discard the recording.\n\n"
                     + "macOS can't detect clashes with other apps' shortcuts — if one doesn't "
                     + "respond, another app or a system shortcut (e.g. Spotlight, input "
                     + "source switching) probably has it; pick a different combination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show floating recording indicator", isOn: $showFloatingIndicator)
                    .onChange(of: showFloatingIndicator) { _, visible in
                        floatingIndicator.isVisible = visible
                    }
            } header: {
                Text("Recording Indicator")
            } footer: {
                Text("A small dot that stays above all windows and expands into a live waveform "
                     + "while recording. Drag it to move it anywhere on screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                microphoneStatusView
                accessibilityStatusView
            }

            Section {
                speechStatusView
            } header: {
                Text("Apple Speech Model")
            } footer: {
                Text("Apple's on-device speech model for your Mac's language transcribes dictations "
                     + "unless another model is selected and loaded on the Models tab. macOS downloads it "
                     + "once, the first time the app runs; after that it works offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Delivery") {
                Toggle("Paste at cursor after dictation", isOn: $settings.autoPasteEnabled)
            }
        }
        .formStyle(.grouped)
        .task {
            await speechService.prepare()
        }
        .task {
            while !Task.isCancelled {
                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                accessibilityTrusted = PasteDelivery.isAccessibilityTrusted
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func setListening(_ listening: Bool) {
        listening ? shortcuts.suspend() : shortcuts.resume()
    }

    // MARK: Speech status

    @ViewBuilder
    private var speechStatusView: some View {
        if speechService.isReady {
            Label("Ready (\(speechService.resolvedLocale.identifier))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else if speechService.isDownloading {
            Label("Downloading model…", systemImage: "arrow.down.circle")
                .foregroundStyle(.orange)
                .font(.callout)
        } else if let err = speechService.loadError {
            VStack(alignment: .leading, spacing: 8) {
                Label(err, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                Button("Download Model") {
                    Task { await speechService.downloadModelIfNeeded() }
                }
            }
        } else {
            Label("Checking availability…", systemImage: "ellipsis.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    // MARK: Microphone status

    @ViewBuilder
    private var microphoneStatusView: some View {
        switch micStatus {
        case .authorized:
            Label("Microphone access granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .notDetermined:
            VStack(alignment: .leading, spacing: 8) {
                Label("Microphone access not yet requested", systemImage: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Button("Request Access") {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Label("Microphone access denied — required to record", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Button("Open System Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: Accessibility status

    @ViewBuilder
    private var accessibilityStatusView: some View {
        if accessibilityTrusted {
            Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Accessibility access required for auto-paste", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Button("Grant Access…") {
                    PasteDelivery.requestAccessibilityPermission()
                    PasteDelivery.openAccessibilitySettings()
                }
                Text("You may need to relaunch TalkToMyMac after granting access.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
