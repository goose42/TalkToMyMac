import SwiftUI
import TalkToMyMacCore

/// Shown at the top of a remote provider's page while a failed call has paused it: why, until
/// when, and a button to resume now. Renders nothing otherwise, and disappears by itself once
/// the pause runs out.
@available(macOS 26.0, *)
struct FormattingPauseSection: View {
    let provider: FormattingProvider
    @Bindable var settings: FormattingSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let pause = settings.formattingPause, pause.isActive(for: provider, at: context.date) {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Formatting paused until \(pause.until.formatted(date: .omitted, time: .shortened))")
                                .fontWeight(.medium)
                            Text("The last call to \(provider.displayName) failed: \(pause.reason). "
                                 + "Dictations are pasted without formatting until then.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    Button("Resume Formatting Now") { settings.resumeFormatting() }
                }
            }
        }
    }
}
