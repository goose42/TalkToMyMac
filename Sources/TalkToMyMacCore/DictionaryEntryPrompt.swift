import Foundation

/// Prompt for generating a dictionary entry's fields from just its written form.
public enum DictionaryEntryPrompt {
    /// Compiled from `Prompts/dictionary-entry.md`.
    public static let instructions = PromptLibrary.dictionaryEntry

    public static func prompt(for written: String) -> String {
        "Term: \(written)"
    }

    /// Builds an entry from the model's raw answer. Context is assembled here from the
    /// neighbour words (minus any that mention the term), because the formatting model
    /// copies words out of `context`. Flags that only apply to one type are normalized.
    public static func entry(written: String, type: DictionaryEntry.EntryType, soundsLike: [String],
                             neighborWords: [String], formatAsCode: Bool, inflect: Bool) -> DictionaryEntry {
        let neighbors = neighborWords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.range(of: written, options: .caseInsensitive) == nil }
        return DictionaryEntry(
            written: written,
            type: type,
            soundsLike: soundsLike,
            context: neighbors.isEmpty ? nil : "appears next to words like " + neighbors.joined(separator: ", "),
            formatAsCode: type == .identifier && formatAsCode,
            inflect: type != .verb || inflect
        )
    }
}

extension DictionaryEntry {
    /// Splits comma-separated text, as typed in Settings, into trimmed non-empty items.
    public static func parseList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func formatList(_ items: [String]) -> String {
        items.joined(separator: ", ")
    }
}
