import SwiftUI
import TalkToMyMacCore

/// Settings tab for choosing the models: which one transcribes speech (Apple's on-device
/// model, or one the app downloads and hosts), and which one formats transcripts (Apple's
/// on-device model, or a remote one on Groq with its API key and model).
@available(macOS 26.0, *)
struct ModelsView: View {
    let groqFormatter: GroqFormatter
    let parakeetService: ParakeetTranscriptionService
    @Bindable var settings: FormattingSettings

    private let keyStore = APIKeyStore.groq
    @State private var keyField = ""
    @State private var hasSavedKey = APIKeyStore.groq.load() != nil
    @State private var testState: TestState = .idle
    @State private var confirmingDelete = false

    private enum TestState {
        case idle
        case testing
        case succeeded(String)
        case failed(String)
    }

    var body: some View {
        Form {
            speechSection

            Section {
                Picker("Formatting model", selection: $settings.provider) {
                    ForEach(FormattingProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
            } header: {
                Text("Provider")
            } footer: {
                Text("This picks the model that formats the transcript. "
                     + "Dictionary suggestions always use the on-device model.")
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

                PriceEditor(model: .groq(settings.groqModel), settings: settings)

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
                         + "If a request fails, the raw transcript is delivered instead. "
                         + "Prices start at Groq's list price; update them if Groq's pricing "
                         + "changes. They're used for cost estimates on the Instrumentation tab.")
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

    // MARK: Speech-to-text

    /// Whether an external model is selected. Turning this off is how the app goes back to
    /// Apple's model, so it also frees the external model's memory.
    private var usesExternalModel: Binding<Bool> {
        Binding(
            get: { settings.transcriptionEngine.isExternal },
            set: { enabled in
                if enabled {
                    settings.transcriptionEngine = .parakeetTDTv3
                    if parakeetService.state == .downloaded {
                        Task { await parakeetService.load() }
                    }
                } else {
                    settings.transcriptionEngine = .appleOnDevice
                    Task { await parakeetService.unload() }
                }
            }
        )
    }

    /// The external model the picker shows — the selected one, or the first while Apple's is.
    private var externalEngine: Binding<TranscriptionEngine> {
        Binding(
            get: { settings.transcriptionEngine.isExternal ? settings.transcriptionEngine : .parakeetTDTv3 },
            set: { settings.transcriptionEngine = $0 }
        )
    }

    private var speechSection: some View {
        Section {
            Toggle("Use an external speech model", isOn: usesExternalModel)

            Picker("Model", selection: externalEngine) {
                ForEach(TranscriptionEngine.allCases.filter(\.isExternal), id: \.self) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .disabled(!settings.transcriptionEngine.isExternal)

            LabeledContent("Status") { parakeetStatusView }

            HStack {
                switch parakeetService.state {
                case .notDownloaded:
                    Button("Download") { Task { await parakeetService.download() } }
                case .downloading, .loading:
                    EmptyView()
                case .downloaded:
                    Button("Load") {
                        settings.transcriptionEngine = .parakeetTDTv3
                        Task { await parakeetService.load() }
                    }
                case .ready:
                    Button("Unload") {
                        settings.transcriptionEngine = .appleOnDevice
                        Task { await parakeetService.unload() }
                    }
                case .failed:
                    Button("Retry") {
                        Task {
                            await parakeetService.load()
                            if case .failed = parakeetService.state { await parakeetService.download() }
                        }
                    }
                }
                if parakeetService.state.isOnDisk {
                    Button("Delete Files…", role: .destructive) { confirmingDelete = true }
                        .disabled(parakeetService.state == .loading)
                }
            }
            .confirmationDialog("Delete the Parakeet model files?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    settings.transcriptionEngine = .appleOnDevice
                    Task { await parakeetService.deleteFiles() }
                }
            } message: {
                Text("Dictation will use Apple's speech model. You can download Parakeet again at any time.")
            }
        } header: {
            Text("Speech-to-Text")
        } footer: {
            Text("Parakeet TDT 0.6B v3 is NVIDIA's speech model, run on-device on the Neural Engine. "
                 + "It understands 25 European languages and is a one-time download of about 600 MB. "
                 + "Until it's loaded — and after you unload it — Apple's on-device model "
                 + "transcribes instead. Nothing you say leaves the Mac either way.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var parakeetStatusView: some View {
        switch parakeetService.state {
        case .notDownloaded:
            Text("Not downloaded").foregroundStyle(.secondary)
        case .downloading:
            HStack {
                ProgressView(value: parakeetService.downloadProgress).frame(width: 120)
                Text("Downloading…").foregroundStyle(.secondary)
            }
        case .downloaded:
            Text("Downloaded, not loaded\(sizeSuffix)").foregroundStyle(.secondary)
        case .loading:
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading…").foregroundStyle(.secondary)
            }
        case .ready:
            Label("Loaded\(sizeSuffix)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var sizeSuffix: String {
        guard let bytes = parakeetService.sizeOnDisk else { return "" }
        return " · \(bytes.formatted(.byteCount(style: .file)))"
    }

    // MARK: Groq

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
