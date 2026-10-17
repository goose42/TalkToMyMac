import SwiftUI

/// A back arrow in the top-left corner of a pushed Settings page, with the page's title.
/// Used instead of the toolbar's back button, which doesn't reliably appear for a navigation
/// stack nested in the Settings split view. ⌘[ also goes back. `trailing` goes in the
/// top-right corner, for page-level controls.
struct BackBar<Trailing: View>: View {
    let title: String?
    let help: String
    let action: () -> Void
    let trailing: Trailing

    init(title: String?, help: String, action: @escaping () -> Void,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.help = help
        self.action = action
        self.trailing = trailing()
    }

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
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

extension BackBar where Trailing == EmptyView {
    init(title: String?, help: String, action: @escaping () -> Void) {
        self.init(title: title, help: help, action: action) { EmptyView() }
    }
}
