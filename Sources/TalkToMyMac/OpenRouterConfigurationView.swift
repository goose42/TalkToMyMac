import SwiftUI
import TalkToMyMacCore

/// OpenRouter's configuration page: the API key (kept in the Keychain), which model formats
/// transcripts, and the prices used for cost estimates.
@available(macOS 26.0, *)
struct OpenRouterConfigurationView: View {
    let openRouterFormatter: OpenRouterFormatter
    @Bindable var settings: FormattingSettings

    private let keyStore = APIKeyStore.openRouter
    @State private var keyField = ""
    @State private var hasSavedKey = APIKeyStore.openRouter.load() != nil
    @State private var testState: TestState = .idle

    private enum TestState {
        case idle
        case testing
        case succeeded(String)
        case failed(String)
    }

    /// One-line status for the provider's row on the Models page.
    static func summary(settings: FormattingSettings) -> String {
        let key = APIKeyStore.openRouter.load() != nil ? "API key saved" : "No API key"
        let paused = settings.formattingPause?.isActive(for: .openRouter) == true ? " · Paused" : ""
        return "\(settings.openRouterModel.displayName) · \(key)\(paused)"
    }

    var body: some View {
        Form {
            FormattingPauseSection(provider: .openRouter, settings: settings)

            Section {
                LabeledContent("API key") {
                    HStack {
                        SecureField(hasSavedKey ? "Saved in Keychain" : "sk-or-…", text: $keyField)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                        Button("Save") { saveKey() }
                            .disabled(keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Clear") { clearKey() }
                            .disabled(!hasSavedKey)
                    }
                }

                HStack {
                    Button("Test Connection") { runTest() }
                        .disabled(!hasSavedKey || isTesting)
                    if isTesting {
                        ProgressView().controlSize(.small)
                    }
                }
                testStatusView
            } header: {
                Text("API Key")
            } footer: {
                Link("Get an API key at openrouter.ai", destination: URL(string: "https://openrouter.ai/settings/keys")!)
                    .font(.caption)
            }

            Section {
                Picker("Model", selection: $settings.openRouterModel) {
                    ForEach(OpenRouterModel.allCases, id: \.self) { model in
                        Text("\(model.displayName) (\(model.rawValue))").tag(model)
                    }
                }
            } header: {
                Text("Model")
            } footer: {
                Text("With OpenRouter selected, each transcript and your formatting instructions "
                     + "are sent to OpenRouter and the model's provider. Free models may log "
                     + "prompts and are rate-limited. "
                     + "If a request fails, the raw transcript is delivered instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                PriceEditor(model: .openRouter(settings.openRouterModel), settings: settings)
            } header: {
                Text("Pricing")
            } footer: {
                Text("These models are free, so prices start at zero; set them if you switch "
                     + "to a paid model. They're used for cost estimates on the Instrumentation tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var isTesting: Bool {
        if case .testing = testState { return true }
        return false
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .idle, .testing:
            if !hasSavedKey {
                Label("No API key saved", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        case .succeeded(let sample):
            Label("Connected — \(sample)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .lineLimit(2)
        case .failed(let reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private func saveKey() {
        let key = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyStore.save(key) {
            hasSavedKey = true
            keyField = ""
            testState = .idle
        } else {
            testState = .failed("Couldn't save the key to the Keychain")
        }
    }

    private func clearKey() {
        keyStore.delete()
        hasSavedKey = false
        testState = .idle
    }

    private func runTest() {
        testState = .testing
        Task {
            switch await openRouterFormatter.testConnection() {
            case .success(let sample): testState = .succeeded(sample)
            case .failure(let error):  testState = .failed(error.localizedDescription)
            }
        }
    }
}
