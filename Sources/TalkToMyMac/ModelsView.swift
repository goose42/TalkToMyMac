import SwiftUI
import TalkToMyMacCore

/// Settings tab for choosing the models: which one transcribes speech (Apple's on-device
/// model, or one the app downloads and hosts), and which one formats transcripts. A provider
/// that needs setup gets a Configuration row leading to its own page.
@available(macOS 26.0, *)
struct ModelsView: View {
    let groqFormatter: GroqFormatter
    let openRouterFormatter: OpenRouterFormatter
    let parakeetService: ParakeetTranscriptionService
    @Bindable var settings: FormattingSettings

    @State private var confirmingDelete = false
    @State private var path: [ProviderConfigurationRoute] = []
    /// Bumped whenever the page reappears, so configuration summaries (e.g. whether an API
    /// key is saved) are re-read after returning from a provider's page.
    @State private var summaryRefresh = 0

    var body: some View {
        NavigationStack(path: $path) {
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

                if settings.provider.hasConfiguration {
                    Section("Configuration") {
                        NavigationLink(value: ProviderConfigurationRoute(provider: settings.provider)) {
                            LabeledContent(settings.provider.displayName) {
                                Text(ProviderConfigurationView.summary(for: settings.provider, settings: settings))
                                    .id(summaryRefresh)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { summaryRefresh += 1 }
            .navigationDestination(for: ProviderConfigurationRoute.self) { route in
                ProviderConfigurationView(provider: route.provider, groqFormatter: groqFormatter,
                                          openRouterFormatter: openRouterFormatter,
                                          settings: settings) { path.removeLast() }
            }
        }
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

            Picker("Language", selection: $settings.parakeetLanguage) {
                Text("Automatic").tag(ParakeetLanguage?.none)
                Divider()
                ForEach(ParakeetLanguage.sortedByName(), id: \.self) { language in
                    Text(language.displayName()).tag(Optional(language))
                }
            }
            .disabled(settings.transcriptionEngine != .parakeetTDTv3)

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
                 + "Automatic lets it detect the language; picking one keeps its output in that "
                 + "language's alphabet (Latin, Cyrillic or Greek). "
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
}
