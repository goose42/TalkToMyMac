import SwiftUI
import TalkToMyMacCore

/// Settings tab for choosing which model formats transcripts: Apple's on-device model, or a
/// remote one on Groq with its API key and model.
@available(macOS 26.0, *)
struct ModelsView: View {
    let groqFormatter: GroqFormatter
    @Bindable var settings: FormattingSettings

    private let keyStore = APIKeyStore.groq
    @State private var keyField = ""
    @State private var hasSavedKey = APIKeyStore.groq.load() != nil
    @State private var testState: TestState = .idle

    private enum TestState {
        case idle
        case testing
        case succeeded(String)
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                Picker("Formatting model", selection: $settings.provider) {
                    ForEach(FormattingProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
            } header: {
                Text("Provider")
            } footer: {
                Text("Speech is always transcribed on-device; this picks the model that formats "
                     + "the transcript. Dictionary suggestions always use the on-device model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("API key") {
                    HStack {
                        SecureField(hasSavedKey ? "Saved in Keychain" : "gsk_…", text: $keyField)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                        Button("Save") { saveKey() }
                            .disabled(keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Clear") { clearKey() }
                            .disabled(!hasSavedKey)
                    }
                }

                Picker("Model", selection: $settings.groqModel) {
                    ForEach(GroqModel.allCases, id: \.self) { model in
                        Text("\(model.displayName) (\(model.rawValue))").tag(model)
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
                Text("Groq")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("With Groq selected, each transcript and your formatting instructions "
                         + "(including the dictionary) are sent to Groq's servers. "
                         + "If a request fails, the raw transcript is delivered instead.")
                    Link("Get an API key at console.groq.com", destination: URL(string: "https://console.groq.com/keys")!)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .disabled(settings.provider != .groq)
        }
        .padding(20)
        .frame(minWidth: 440)
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
            switch await groqFormatter.testConnection() {
            case .success(let sample): testState = .succeeded(sample)
            case .failure(let error):  testState = .failed(error.localizedDescription)
            }
        }
    }
}
