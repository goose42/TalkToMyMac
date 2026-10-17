import SwiftUI
import TalkToMyMacCore

/// Groq's configuration page: the API key (kept in the Keychain), which model formats
/// transcripts, and the prices used for cost estimates.
@available(macOS 26.0, *)
struct GroqConfigurationView: View {
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

    /// One-line status for the provider's row on the Models page.
    static func summary(settings: FormattingSettings) -> String {
        let key = APIKeyStore.groq.load() != nil ? "API key saved" : "No API key"
        return "\(settings.groqModel.displayName) · \(key)"
    }

    var body: some View {
        Form {
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
                Link("Get an API key at console.groq.com", destination: URL(string: "https://console.groq.com/keys")!)
                    .font(.caption)
            }

            Section {
                Picker("Model", selection: $settings.groqModel) {
                    ForEach(GroqModel.allCases, id: \.self) { model in
                        Text("\(model.displayName) (\(model.rawValue))").tag(model)
                    }
                }
            } header: {
                Text("Model")
            } footer: {
                Text("With Groq selected, each transcript and your formatting instructions "
                     + "are sent to Groq's servers. "
                     + "If a request fails, the raw transcript is delivered instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                PriceEditor(model: .groq(settings.groqModel), settings: settings)
            } header: {
                Text("Pricing")
            } footer: {
                Text("Prices start at Groq's list price; update them if Groq's pricing "
                     + "changes. They're used for cost estimates on the Instrumentation tab.")
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
            switch await groqFormatter.testConnection() {
            case .success(let sample): testState = .succeeded(sample)
            case .failure(let error):  testState = .failed(error.localizedDescription)
            }
        }
    }
}

/// Editable per-million-token prices for one remote model, used for the cost estimates on
/// the Instrumentation tab.
@available(macOS 26.0, *)
private struct PriceEditor: View {
    let model: FormattingModel
    @Bindable var settings: FormattingSettings

    var body: some View {
        if let price = settings.price(for: model) {
            priceField("Input price", value: price.inputPerMillion) { $0.inputPerMillion = $1 }
            priceField("Cached input price", value: price.cachedInputPerMillion) { $0.cachedInputPerMillion = $1 }
            priceField("Output price", value: price.outputPerMillion) { $0.outputPerMillion = $1 }
            if let listPrice = GroqModel(rawValue: model.modelID)?.listPrice, price != listPrice {
                Button("Reset to List Price") { settings.resetPrice(for: model) }
            }
        }
    }

    private func priceField(_ label: String, value: Double,
                            update: @escaping (inout TokenPrice, Double) -> Void) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(label, value: Binding(
                    get: { value },
                    set: { newValue in
                        guard var price = settings.price(for: model), newValue >= 0 else { return }
                        update(&price, newValue)
                        settings.setPrice(price, for: model)
                    }
                ), format: .currency(code: "USD").precision(.fractionLength(2...4)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                Text("per 1M tokens")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
