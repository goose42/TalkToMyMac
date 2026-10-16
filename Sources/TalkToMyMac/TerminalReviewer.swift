import AppKit
import TalkToMyMacCore

/// Terminal emulators, where a paste can't be corrected afterwards: ⇧← doesn't select text
/// there, so dictionary replacements have to be settled before pasting.
enum TerminalApps {
    static let bundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "com.raphaelamorim.rio",
    ]

    /// Whether the app that would receive a paste is a terminal. Main thread only.
    static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier.map(bundleIDs.contains) ?? false
    }
}

/// When dictating into a terminal, pauses the pipeline after cleanup to let the user choose,
/// for each dictionary replacement, between the term and the word actually spoken — then
/// carries on with their choice. Everywhere else it passes the text straight through, and
/// replacements can be undone after pasting instead.
/// `@unchecked Sendable`: holds only immutable references; UI work hops to the main thread.
final class TerminalReviewer: TranscriptReviewing, @unchecked Sendable {
    private let settings: FormattingSettings
    private let indicator: FloatingIndicatorController

    init(settings: FormattingSettings, indicator: FloatingIndicatorController) {
        self.settings = settings
        self.indicator = indicator
    }

    func review(raw: String, cleaned: String) async -> String? {
        guard let review = ReplacementReview(raw: raw, text: cleaned, dictionary: settings.dictionaryEntries)
        else { return cleaned }
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [settings, indicator] in
                MainActor.assumeIsolated {
                    guard settings.autoPasteEnabled, TerminalApps.isFrontmost, indicator.isVisible else {
                        continuation.resume(returning: cleaned)
                        return
                    }
                    indicator.askBeforePaste(review) { continuation.resume(returning: $0) }
                }
            }
        }
    }
}
