import Foundation

/// Each place the dictionary swapped a term into the text, so the user can put back the word
/// actually spoken, occurrence by occurrence. Works against the cleaned or pasted text, so it
/// also works after LLM formatting as long as the written form survived it.
public struct ReplacementReview: Equatable, Sendable {
    public struct Occurrence: Equatable, Sendable {
        public let written: String
        /// What was said instead, as transcribed.
        public let original: String
        /// Where `written` sits in the reviewed text.
        let range: NSRange
    }

    public let pastedText: String
    /// In order of appearance in `pastedText`.
    public let occurrences: [Occurrence]

    /// Matches the dictionary's replacements in `raw` to the written forms in `text` by order
    /// of appearance, counting terms the speech model already got right so they aren't
    /// offered. If formatting changed how often a term appears, the order can't be trusted
    /// and every occurrence of it is offered instead. Nil if there's nothing to offer.
    public init?(raw: String, text: String, dictionary: [DictionaryEntry]) {
        let rawNS = raw as NSString
        let matches = DictionaryReplacement.termMatches(dictionary, in: raw)
        var occurrences: [Occurrence] = []
        var seen = Set<String>()
        for written in matches.map(\.written) where seen.insert(written).inserted {
            let replaced = matches
                .filter { $0.written == written }
                .map { (range: $0.range, original: rawNS.substring(with: $0.range)) }
                .filter { $0.original != written }
            guard let firstOriginal = replaced.first?.original else { continue }
            let alreadyRight = Self.ranges(of: written, in: raw)
                .filter { range in !replaced.contains { NSIntersectionRange($0.range, range).length > 0 } }
                .map { (range: $0, original: String?.none) }
            let spoken = (replaced.map { (range: $0.range, original: Optional($0.original)) } + alreadyRight)
                .sorted { $0.range.location < $1.range.location }
            let inText = Self.ranges(of: written, in: text)
            if spoken.count == inText.count {
                for (said, range) in zip(spoken, inText) {
                    if let original = said.original {
                        occurrences.append(Occurrence(written: written, original: original, range: range))
                    }
                }
            } else {
                occurrences += inText.map { Occurrence(written: written, original: firstOriginal, range: $0) }
            }
        }
        guard !occurrences.isEmpty else { return nil }
        self.pastedText = text
        self.occurrences = occurrences.sorted { $0.range.location < $1.range.location }
    }

    /// `pastedText` with the occurrences at `reverted` (indices into `occurrences`) swapped
    /// back to what was spoken.
    public func text(reverting reverted: Set<Int>) -> String {
        let output = NSMutableString(string: pastedText)
        for index in occurrences.indices.reversed() where reverted.contains(index) {
            output.replaceCharacters(in: occurrences[index].range, with: occurrences[index].original)
        }
        return output as String
    }

    /// Up to three words either side of an occurrence, for telling occurrences apart, with
    /// "…" where the text goes on.
    public func context(of index: Int) -> (before: String, after: String) {
        let text = pastedText as NSString
        let range = occurrences[index].range
        let before = Self.clip(text.substring(to: range.location), pattern: "(?<!\\S)(?:\\S+\\s+){0,3}\\S*$")
        let after = Self.clip(text.substring(from: NSMaxRange(range)), pattern: "^\\S*(?:\\s+\\S+){0,3}")
        return (before.clipped ? "…" + before.kept : before.kept, after.clipped ? after.kept + "…" : after.kept)
    }

    /// How to turn `old` into `new` from the end of it: delete `deleteCount` characters
    /// (as the user would with ⌫) and type `insert`. Only the tail after the common prefix
    /// changes, which keeps the keystrokes sent to the other app to a minimum.
    public static func edit(from old: String, to new: String) -> (deleteCount: Int, insert: String) {
        let prefix = zip(old, new).prefix { $0 == $1 }.count
        return (old.count - prefix, String(new.dropFirst(prefix)))
    }

    /// Whole-word, exactly-cased occurrences of `word` in `text`.
    private static func ranges(of word: String, in text: String) -> [NSRange] {
        let pattern = DictionaryReplacement.wordBoundaryBefore + NSRegularExpression.escapedPattern(for: word)
            + DictionaryReplacement.wordBoundaryAfter
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
    }

    /// The part of `text` that `pattern` matches, and whether anything but whitespace was left out.
    private static func clip(_ text: String, pattern: String) -> (kept: String, clipped: Bool) {
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        else { return ("", !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        let rest = ns.replacingCharacters(in: match.range, with: "")
        return (ns.substring(with: match.range), !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
