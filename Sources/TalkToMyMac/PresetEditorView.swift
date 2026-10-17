import SwiftUI
import TalkToMyMacCore

/// Navigation value for the selected preset's editor page.
struct PresetEditorRoute: Hashable {
    let preset: PromptPreset
}

/// Page for editing the formatting instructions seeded by the selected preset, under a back
/// bar to the Formatting page. Edits go to `customInstructions` — the text actually sent to
/// the model — so picking another preset replaces them with that preset's text.
@available(macOS 26.0, *)
struct PresetEditorView: View {
    let preset: PromptPreset
    @Bindable var settings: FormattingSettings
    /// Returns to the Formatting page.
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BackBar(title: "Edit Preset · \(preset.displayName)", help: "Back to Formatting", action: onBack)
            Divider()
            Form {
                Section {
                    TextEditor(text: $settings.customInstructions)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 240)
                        .scrollContentBackground(.hidden)

                    HStack {
                        Text(preset.isEdited(settings.customInstructions) ? "Edited" : "Built-in text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(preset == .custom ? "Clear" : "Reset to Preset") {
                            settings.resetCustomInstructionsToCurrentPreset()
                        }
                        .disabled(!preset.isEdited(settings.customInstructions))
                    }
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("This is the system prompt sent to the formatting model with each "
                         + "transcript. Changes save as you type. Choosing a different preset "
                         + "replaces them with that preset's text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: .infinity)
        }
        // The back bar replaces the toolbar's own back button, which doesn't reliably appear
        // for a stack nested in the Settings split view.
        .navigationBarBackButtonHidden(true)
        .navigationTitle("Edit Preset")
    }
}
