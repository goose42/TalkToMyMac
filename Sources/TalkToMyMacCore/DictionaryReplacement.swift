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

    /// One pass avoids cascading replacements; Unicode boundaries preserve words like café.
    private static func replacing(_ entries: [DictionaryEntry], in text: String) -> String {
        let pairs = entries.flatMap { entry in
            entry.soundsLike
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { (phrase: $0, written: entry.written) }
        }
        .sorted { $0.phrase.count > $1.phrase.count }
        guard !pairs.isEmpty else { return text }
        let alternatives = pairs.map { NSRegularExpression.escapedPattern(for: $0.phrase) }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{M}\\p{N}_])(?:\(alternatives))(?![\\p{L}\\p{M}\\p{N}_])",
            options: .caseInsensitive
        ) else { return text }
        let source = text as NSString
        let output = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let phrase = source.substring(with: match.range)
            if let pair = pairs.first(where: { $0.phrase.caseInsensitiveCompare(phrase) == .orderedSame }) {
                output.replaceCharacters(in: match.range, with: pair.written)
            }
        }
        return output as String
    }
}
