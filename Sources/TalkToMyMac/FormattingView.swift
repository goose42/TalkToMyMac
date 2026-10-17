import FoundationModels
import SwiftUI
import TalkToMyMacCore

/// Settings tab for the formatting steps: deterministic cleanup on/off, then the LLM step's
/// on/off and prompt preset (its instructions are edited on their own page), and the word
/// count a transcript must exceed to be worth formatting.
@available(macOS 26.0, *)
struct FormattingView: View {
    let formatter: FoundationModelFormatter
    @Bindable var settings: FormattingSettings

    @State private var path: [PresetEditorRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            form
                .navigationDestination(for: PresetEditorRoute.self) { route in
                    PresetEditorView(preset: route.preset, settings: settings) { path.removeLast() }
                }
        }
    }

    private var form: some View {
        Form {
            Section {
                Toggle("Enable deterministic cleanup", isOn: $settings.deterministicCleanupEnabled)
            } header: {
                Text("Cleanup")
            } footer: {
                Text("Removes filler words, self-corrections and stutters, turns spoken punctuation "
                     + "(“comma”, “new line”), numbers and dictated emails into text — "
                     + "without a model. Runs before LLM formatting, and on its own when LLM "
                     + "formatting is off. Your dictionary’s sounds-like fixes always apply, "
                     + "whether or not this is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("LLM Formatting") {
                Toggle("Enable LLM formatting", isOn: $settings.isEnabled)

                Picker("Preset", selection: $settings.preset) {
                    ForEach(PromptPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .disabled(!settings.isEnabled)

                NavigationLink(value: PresetEditorRoute(preset: settings.preset)) {
                    LabeledContent("Edit Preset") {
                        Text(settings.preset.isEdited(settings.customInstructions) ? "Edited" : "Built-in text")
                    }
                }
                .disabled(!settings.isEnabled)

                formattingStatusView
            }

            Section {
                Toggle("Skip formatting for short dictations", isOn: $settings.skipShortDictations)

                Stepper(value: $settings.formattingWordThreshold, in: 1...50) {
                    Text("Format only above \(settings.formattingWordThreshold) "
                         + (settings.formattingWordThreshold == 1 ? "word" : "words"))
                }
                .disabled(!settings.skipShortDictations)
            } header: {
                Text("Short Dictations")
            } footer: {
                Text("Transcripts at or below this word count are delivered as-is, without the "
                     + "LLM step — a word or two, like a quick correction, rarely needs formatting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.isEnabled)
        }
        .formStyle(.grouped)
    }

    // MARK: Formatting status

    @ViewBuilder
    private var formattingStatusView: some View {
        if let pause = settings.activePause {
            Label("\(pause.provider.displayName) is paused until "
                  + "\(pause.until.formatted(date: .omitted, time: .shortened)) after a failed call "
                  + "— resume in the Models tab",
                  systemImage: "pause.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        } else {
            providerStatusView
        }
    }

    @ViewBuilder
    private var providerStatusView: some View {
        switch settings.provider {
        case .appleOnDevice:
            onDeviceStatusView
        case .groq:
            Label("Using Groq · \(settings.groqModel.rawValue) — change in the Models tab",
                  systemImage: "cloud.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .openRouter:
            Label("Using OpenRouter · \(settings.openRouterModel.rawValue) — change in the Models tab",
                  systemImage: "cloud.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var onDeviceStatusView: some View {
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
}
