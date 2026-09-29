import FoundationModels
import SwiftUI
import TalkToMyMacCore

/// Settings tab for the LLM formatting step: on/off, prompt preset and instructions, and
/// the minimum recording length worth formatting.
@available(macOS 26.0, *)
struct FormattingView: View {
    let formatter: FoundationModelFormatter
    @Bindable var settings: FormattingSettings

    var body: some View {
        Form {
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

                Stepper(value: $settings.minimumFormattingSeconds, in: 0.5...30, step: 0.5) {
                    Text("Minimum length: \(settings.minimumFormattingSeconds, specifier: "%.1f") s")
                }
                .disabled(!settings.skipShortDictations)
            } header: {
                Text("Short Dictations")
            } footer: {
                Text("Recordings shorter than the minimum deliver the raw transcript without the "
                     + "LLM step — a word or two, like a quick correction, rarely needs formatting. "
                     + "Length is the whole recording, including any pause before or after speaking.")
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
