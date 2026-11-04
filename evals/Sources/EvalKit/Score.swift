import Foundation
import TalkToMyMacCore

/// How close a model's output is to the expected text.
public struct Score: Codable, Equatable, Sendable {
    /// Equal after trimming each line's surrounding whitespace and collapsing runs of spaces.
    /// Line breaks, capitalisation and punctuation still count.
    public let exactMatch: Bool
    /// Word edits (Levenshtein over whitespace-separated words, as in `WordDiff`) between the two.
    public let changedWords: Int
    /// 1 − changedWords / the longer text's word count; 1 when both are empty.
    public let similarity: Double

    public init(expected: String, actual: String) {
        let expected = Self.normalize(expected)
        let actual = Self.normalize(actual)
        exactMatch = expected == actual
        changedWords = WordDiff.changedWords(from: expected, to: actual)
        let longest = max(WordDiff.wordCount(expected), WordDiff.wordCount(actual))
        similarity = longest == 0 ? 1 : 1 - Double(changedWords) / Double(longest)
    }

    /// The score of a run that produced no output.
    public static let failed = Score(exactMatch: false, changedWords: 0, similarity: 0)

    private init(exactMatch: Bool, changedWords: Int, similarity: Double) {
        self.exactMatch = exactMatch
        self.changedWords = changedWords
        self.similarity = similarity
    }

    static func normalize(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
