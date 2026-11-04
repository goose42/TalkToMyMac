import XCTest
@testable import EvalKit

final class ScoringTests: XCTestCase {

    func testIdenticalTextIsAnExactMatch() {
        let score = Score(expected: "Hello there.", actual: "Hello there.")
        XCTAssertTrue(score.exactMatch)
        XCTAssertEqual(score.similarity, 1)
        XCTAssertEqual(score.changedWords, 0)
    }

    func testIgnoresSurroundingAndTrailingWhitespace() {
        let score = Score(expected: "Make it real-time.\n- Stream tokens",
                          actual: "  Make it  real-time.  \n- Stream tokens\n")
        XCTAssertTrue(score.exactMatch)
    }

    /// Line breaks carry structure (bullets, paragraphs), so they still count.
    func testLineBreaksMatter() {
        XCTAssertFalse(Score(expected: "A.\n- b", actual: "A. - b").exactMatch)
    }

    func testCapitalisationAndPunctuationMatter() {
        XCTAssertFalse(Score(expected: "Why?", actual: "why").exactMatch)
    }

    func testSimilarityIsTheShareOfWordsUnchanged() {
        let score = Score(expected: "write a test for mergeRecords", actual: "write a test for dedupe")
        XCTAssertEqual(score.changedWords, 1)
        XCTAssertEqual(score.similarity, 0.8, accuracy: 0.0001)
    }

    func testSimilarityUsesTheLongerText() {
        let score = Score(expected: "one two", actual: "one two three four")
        XCTAssertEqual(score.similarity, 0.5, accuracy: 0.0001)
    }

    func testEmptyExpectedAndEmptyActualMatch() {
        let score = Score(expected: "", actual: "  ")
        XCTAssertTrue(score.exactMatch)
        XCTAssertEqual(score.similarity, 1)
    }

    func testEmptyActualScoresZero() {
        XCTAssertEqual(Score(expected: "Hi there.", actual: "").similarity, 0)
    }
}
