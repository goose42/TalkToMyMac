import SwiftUI
import TalkToMyMacCore

/// Navigation value for a formatting provider's configuration page.
struct ProviderConfigurationRoute: Hashable {
    let provider: FormattingProvider
}

/// The configuration page of a formatting provider, under a back bar to the Models page.
///
/// Adding a provider with settings: give it a `FormattingProvider` case that returns true
/// from `hasConfiguration`, write its page, and add it to `page` and `summary(for:settings:)`.
@available(macOS 26.0, *)
struct ProviderConfigurationView: View {
    let provider: FormattingProvider
    let groqFormatter: GroqFormatter
    @Bindable var settings: FormattingSettings
    /// Returns to the Models page.
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BackBar(title: provider.displayName, help: "Back to Models", action: onBack)
            Divider()
            page
                .frame(maxHeight: .infinity)
        }
        // The back bar replaces the toolbar's own back button, which doesn't reliably appear
        // for a stack nested in the Settings split view.
        .navigationBarBackButtonHidden(true)
        .navigationTitle(provider.displayName)
    }

    @ViewBuilder
    private var page: some View {
        switch provider {
        case .groq:
            GroqConfigurationView(groqFormatter: groqFormatter, settings: settings)
        case .appleOnDevice:
            ContentUnavailableView("Nothing to Configure", systemImage: "checkmark.circle",
                                   description: Text("Apple Intelligence runs on this Mac and needs no setup."))
        }
    }

    /// One-line status for the provider's row on the Models page.
    static func summary(for provider: FormattingProvider, settings: FormattingSettings) -> String {
        switch provider {
        case .groq:          return GroqConfigurationView.summary(settings: settings)
        case .appleOnDevice: return ""
        }
    }
}
