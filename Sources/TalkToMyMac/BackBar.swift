import SwiftUI

/// A back arrow in the top-left corner of a pushed Settings page, with the page's title.
/// Used instead of the toolbar's back button, which doesn't reliably appear for a navigation
/// stack nested in the Settings split view. ⌘[ also goes back.
struct BackBar: View {
    let title: String?
    let help: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("[", modifiers: .command)
            .help("\(help) (⌘[)")

            if let title {
                Text(title).font(.headline)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
