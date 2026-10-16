import Foundation

/// Rewrites the dictionary's known mis-hearings (`sounds_like`) as each term's `written` form,
/// without a model. Adapted from BetterWispr's `VocabularyProcessor`.
public enum DictionaryReplacement {
    /// Applies the entries whose written form is a term rather than a spoken command.
    public static func apply(_ entries: [DictionaryEntry], to text: String) -> String {
        replacing(entries.filter { !VoiceCommands.isSpokenCommand($0.written) }, in: text)
    }

    /// Applies only the entries written as a spoken command, so "Kocia Mark" can become
    /// "question mark" before voice commands run.
    public static func commands(_ entries: [DictionaryEntry], in text: String) -> String {
        replacing(entries.filter { VoiceCommands.isSpokenCommand($0.written) }, in: text)
    }

    /// Where `apply` would swap in a term (not a spoken command) in `text`, in order.
    static func termMatches(_ entries: [DictionaryEntry], in text: String) -> [(range: NSRange, written: String)] {
        matches(entries.filter { !VoiceCommands.isSpokenCommand($0.written) }, in: text)
    }

    /// Letters, marks, digits and underscores count as word characters on either side.
    static let wordBoundaryBefore = "(?<![\\p{L}\\p{M}\\p{N}_])"
    static let wordBoundaryAfter = "(?![\\p{L}\\p{M}\\p{N}_])"

    /// One pass avoids cascading replacements; Unicode boundaries preserve words like café.
    private static func replacing(_ entries: [DictionaryEntry], in text: String) -> String {
        let output = NSMutableString(string: text)
        for match in matches(entries, in: text).reversed() {
            output.replaceCharacters(in: match.range, with: match.written)
        }
        return output as String
    }

    /// Every sounds-like phrase found in `text`, longest phrase first where they overlap.
    private static func matches(_ entries: [DictionaryEntry], in text: String) -> [(range: NSRange, written: String)] {
        let pairs = entries.flatMap { entry in
            entry.soundsLike
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { (phrase: $0, written: entry.written) }
        }
        .sorted { $0.phrase.count > $1.phrase.count }
        guard !pairs.isEmpty else { return [] }
        let alternatives = pairs.map { NSRegularExpression.escapedPattern(for: $0.phrase) }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(
            pattern: wordBoundaryBefore + "(?:\(alternatives))" + wordBoundaryAfter,
            options: .caseInsensitive
        ) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let phrase = source.substring(with: match.range)
            return pairs.first { $0.phrase.caseInsensitiveCompare(phrase) == .orderedSame }
                .map { (range: match.range, written: $0.written) }
        }
    }
}
