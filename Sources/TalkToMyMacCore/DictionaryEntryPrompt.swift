import Foundation

/// Prompt for generating a dictionary entry's fields from just its written form.
public enum DictionaryEntryPrompt {
    public static let instructions = """
    You help a user build a dictionary for their dictation app. The user speaks; a \
    speech-to-text model transcribes; a second model later uses this dictionary to fix \
    terms the speech model mis-heard. Given a term exactly as the user writes it, describe it:

    - type: noun, proper_noun, verb, adjective, identifier, or acronym. Use identifier for \
    code symbols (functions, variables, classes, files, CLI commands), acronym for \
    abbreviations written as letters, proper_noun for product, project and company names.
    - soundsLike: 2 to 4 ways a speech-to-text model might write the whole term when it is \
    spoken aloud: real English words or phrases that sound like it, or the term spelled out \
    as separate spoken words. Each item must cover the whole term, never just one part of \
    it. Never include the term itself or other correct spellings of it.
    - neighborWords: 3 or 4 ordinary words that often appear in the same sentence as the \
    term. Never include the term itself, its expansion, or other spellings of it.
    - formatAsCode: true only for identifiers that belong in backticks.
    - inflect: false only for verbs that must never change form.

    Examples (do not reuse their values for other terms):
    Term: useState → identifier; soundsLike: "use state", "you state"; neighborWords: \
    component, hook, render, value
    Term: GraphQL → proper_noun; soundsLike: "graph cue el", "graph ql", "graphic you all"; \
    neighborWords: query, schema, resolver, API
    """

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
