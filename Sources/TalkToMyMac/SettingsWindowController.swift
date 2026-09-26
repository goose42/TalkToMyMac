import AppKit
import FoundationModels
import SwiftUI
import TalkToMyMacCore

/// Manages the settings window. Call `showWindow()` to open or bring to front.
@available(macOS 26.0, *)
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let speechService: SpeechTranscriptionService
    private let formatter: FoundationModelFormatter
    private let settings: FormattingSettings
    private let shortcuts: ShortcutManager

    init(speechService: SpeechTranscriptionService, formatter: FoundationModelFormatter,
         settings: FormattingSettings, shortcuts: ShortcutManager) {
        self.speechService = speechService
        self.formatter = formatter
        self.settings = settings
        self.shortcuts = shortcuts
    }

    func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(speechService: speechService, formatter: formatter, settings: settings,
                                    shortcuts: shortcuts)
        let hostingController = NSHostingController(rootView: settingsView)

        let win = NSWindow(contentViewController: hostingController)
        win.title = "TalkToMyMac Settings"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 500, height: 720))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }
}

// MARK: - SwiftUI Settings View

@available(macOS 26.0, *)
private struct SettingsView: View {
    let speechService: SpeechTranscriptionService
    let formatter: FoundationModelFormatter
    @Bindable var settings: FormattingSettings
    let shortcuts: ShortcutManager

    @State private var accessibilityTrusted = PasteDelivery.isAccessibilityTrusted

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

            Section("Speech") {
                speechStatusView
            }

            Section("Formatting") {
                Toggle("Enable LLM formatting", isOn: $settings.isEnabled)

                Picker("Preset", selection: $settings.preset) {
                    ForEach(PromptPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .disabled(!settings.isEnabled)

                TextEditor(text: $settings.customInstructions)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .disabled(!settings.isEnabled)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )

                Button("Reset to Preset") {
                    settings.resetCustomInstructionsToCurrentPreset()
                }
                .disabled(!settings.isEnabled)

                formattingStatusView
            }

            Section("Delivery") {
                Toggle("Paste at cursor after dictation", isOn: $settings.autoPasteEnabled)
                accessibilityStatusView
            }
        }
        .padding(20)
        .frame(minWidth: 440)
        .task {
            await speechService.prepare()
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

    // MARK: Formatting status

    @ViewBuilder
    private var formattingStatusView: some View {
        switch formatter.availability {
        case .available:
            Label("Apple Intelligence: available", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .unavailable(let reason):
            Label("Apple Intelligence: \(describe(reason))", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "this Mac doesn't support Apple Intelligence"
        case .appleIntelligenceNotEnabled:
            return "enable Apple Intelligence in System Settings"
        case .modelNotReady:
            return "model is still downloading"
        @unknown default:
            return "unavailable"
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
                    // The grant happens in System Settings, outside our process — poll
                    // briefly afterward to pick it up without requiring a relaunch.
                    for delay in [1.0, 2.0, 4.0, 8.0, 15.0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            accessibilityTrusted = PasteDelivery.isAccessibilityTrusted
                        }
                    }
                }
                Text("You may need to relaunch TalkToMyMac after granting access.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
