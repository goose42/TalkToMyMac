import XCTest
@testable import TalkToMyMacCore

final class WordDiffTests: XCTestCase {

    func testWordCountSplitsOnAnyWhitespace() {
        XCTAssertEqual(WordDiff.wordCount("  hello   big\tworld\n"), 3)
        XCTAssertEqual(WordDiff.wordCount(""), 0)
    }

    func testIdenticalTextHasNoChanges() {
        XCTAssertEqual(WordDiff.changedWords(from: "the quick fox", to: "the quick fox"), 0)
    }

    func testWhitespaceOnlyDifferencesAreNotChanges() {
        XCTAssertEqual(WordDiff.changedWords(from: "the  quick\nfox", to: "the quick fox"), 0)
    }

    func testCapitalisationAndPunctuationCountAsChanges() {
        // "hello" → "Hello,", "world" → "world." — two substitutions.
        XCTAssertEqual(WordDiff.changedWords(from: "hello world", to: "Hello, world."), 2)
    }

    func testRemovedFillerWords() {
        XCTAssertEqual(WordDiff.changedWords(from: "so um I think uh yes", to: "so I think yes"), 2)
    }

    func testInsertedWords() {
        XCTAssertEqual(WordDiff.changedWords(from: "send email", to: "send the email now"), 2)
    }

    func testEmptySides() {
        XCTAssertEqual(WordDiff.changedWords(from: "", to: "one two"), 2)
        XCTAssertEqual(WordDiff.changedWords(from: "one two three", to: ""), 3)
        XCTAssertEqual(WordDiff.changedWords(from: "", to: ""), 0)
    }

    func testMixedEdits() {
        // substitute "cat"→"dog", delete "very", insert "today"
        XCTAssertEqual(
            WordDiff.changedWords(from: "the very lazy cat sleeps", to: "the lazy dog sleeps today"),
            3
        )
    }
}
