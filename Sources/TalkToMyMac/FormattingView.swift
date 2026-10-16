import FoundationModels
import SwiftUI
import TalkToMyMacCore

/// Settings tab for the formatting steps: deterministic cleanup on/off, then the LLM step's
/// on/off, prompt preset and instructions, and the word count a transcript must exceed to
/// be worth formatting.
@available(macOS 26.0, *)
struct FormattingView: View {
    let formatter: FoundationModelFormatter
    @Bindable var settings: FormattingSettings

    var body: some View {
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
        .padding(20)
        .frame(minWidth: 440)
    }

    // MARK: Formatting status

    @ViewBuilder
    private var formattingStatusView: some View {
        switch settings.provider {
        case .appleOnDevice:
            onDeviceStatusView
        case .groq:
            Label("Using Groq · \(settings.groqModel.rawValue) — change in the Models tab",
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
