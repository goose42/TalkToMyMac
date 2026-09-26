/// Word-level comparison of a raw transcript against its formatted version.
///
/// Words are whitespace-separated tokens compared exactly, so a change in capitalisation or
/// attached punctuation ("hello" → "Hello,") counts as a changed word — those are exactly
/// the kinds of fixes the LLM makes.
public enum WordDiff {
    public static func words(in text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
    }

    public static func wordCount(_ text: String) -> Int {
        words(in: text).count
    }

    /// Minimum number of word substitutions, insertions, and deletions that turn `original`
    /// into `revised` (Levenshtein distance over words).
    public static func changedWords(from original: String, to revised: String) -> Int {
        let a = words(in: original)
        let b = words(in: revised)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        // Two rolling rows of the DP table: O(len(b)) memory.
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
