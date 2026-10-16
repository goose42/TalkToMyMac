import Foundation

/// fzf-style fuzzy matching: the query's characters must appear in the candidate in order,
/// not necessarily next to each other ("otl" matches "OTel"). Matches that start words, run
/// together, or skip fewer characters score higher.
public enum FuzzyMatch {
    private static let matchScore = 16
    private static let boundaryBonus = 8
    private static let camelCaseBonus = 7
    private static let consecutiveBonus = 4
    private static let gapStartPenalty = 3
    private static let gapExtensionPenalty = 1
    private static let exactBonus = 1000
    private static let separators: Set<Character> = [" ", "-", "_", ".", "/"]

    /// Score of `query` as a subsequence of `candidate`, ignoring case, diacritics and
    /// whitespace in the query, or nil if it isn't one. Higher is better; an empty query
    /// matches everything with a score of 0.
    public static func score(_ query: String, in candidate: String) -> Int? {
        let needle = query.filter { !$0.isWhitespace }.map(folded)
        guard !needle.isEmpty else { return 0 }

        let original = Array(candidate)
        let haystack = original.map(folded)
        guard needle.count <= haystack.count else { return nil }

        let bonuses = original.indices.map { bonus(at: $0, in: original) }
        var best: Int?
        // Greedy from each place the first character could match; dictionary terms are
        // short, so trying every start is cheap and finds e.g. a later word-start match.
        for start in haystack.indices where haystack[start] == needle[0] {
            guard let score = greedyScore(needle, haystack, bonuses, from: start) else { break }
            best = max(best ?? score, score)
        }
        guard var result = best else { return nil }
        if needle == haystack.filter({ !$0.allSatisfy(\.isWhitespace) }) {
            result += exactBonus
        }
        return result
    }

    /// Scores matching `needle` starting at `start`, taking each later character at its
    /// first occurrence. Nil if the rest of the needle doesn't fit.
    private static func greedyScore(_ needle: [String], _ haystack: [String], _ bonuses: [Int],
                                    from start: Int) -> Int? {
        // The first character carries the most weight, as in fzf.
        var score = -start * gapExtensionPenalty + matchScore + bonuses[start] * 2
        var position = start
        var runBonus = bonuses[start]
        for character in needle.dropFirst() {
            guard let next = haystack[(position + 1)...].firstIndex(of: character) else { return nil }
            let gap = next - position - 1
            position = next
            if gap == 0 {
                // Characters continuing a run share the bonus of the run's start.
                runBonus = max(runBonus, bonuses[position], consecutiveBonus)
                score += matchScore + runBonus
            } else {
                runBonus = bonuses[position]
                score += matchScore + runBonus - gapStartPenalty - (gap - 1) * gapExtensionPenalty
            }
        }
        return score
    }

    /// Bonus for a match at `index`: the start of the candidate, after a separator, or a
    /// lower-to-upper camelCase hump.
    private static func bonus(at index: Int, in characters: [Character]) -> Int {
        guard index > 0 else { return boundaryBonus }
        let previous = characters[index - 1]
        if separators.contains(previous) || previous.isWhitespace { return boundaryBonus }
        if previous.isLowercase, characters[index].isUppercase { return camelCaseBonus }
        return 0
    }

    private static func folded(_ character: Character) -> String {
        String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
