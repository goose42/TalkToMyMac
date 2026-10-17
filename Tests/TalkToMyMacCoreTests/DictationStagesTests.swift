import XCTest
@testable import TalkToMyMacCore

final class DictationStagesTests: XCTestCase {

    // MARK: Cleanup

    func testCleanupNotRecordedForOlderDictations() {
        let stages = DictationStages(raw: "um hi", cleanup: .notRecorded, final: "um hi", formatting: nil)
        XCTAssertEqual(stages.cleanup, .notRecorded)
    }

    func testCleanupOffWhenItDidntRun() {
        let stages = DictationStages(raw: "um hi", cleanup: .recorded(nil), final: "um hi", formatting: nil)
        XCTAssertEqual(stages.cleanup, .off)
    }

    func testCleanupCountsChangedWordsAgainstTheRawText() {
        let stages = DictationStages(raw: "um I I think so", cleanup: .recorded("I think so"),
                                     final: "I think so", formatting: nil)
        XCTAssertEqual(stages.cleanup, .applied(changedWords: 2))
    }

    func testCleanupChangeCountUnknownWithoutRawText() {
        let stages = DictationStages(raw: nil, cleanup: .recorded("I think so"), final: "I think so", formatting: nil)
        XCTAssertEqual(stages.cleanup, .applied(changedWords: nil))
    }

    // MARK: Formatting

    func testFormattingNotRecordedWithoutMetrics() {
        let stages = DictationStages(raw: "hi", cleanup: .recorded(nil), final: "Hi.", formatting: nil)
        XCTAssertEqual(stages.formatting, .notRecorded)
    }

    func testFormattingSkippedWhenNotAttempted() {
        let stages = DictationStages(raw: "hi", cleanup: .recorded(nil), final: "hi",
                                     formatting: .init(attempted: false, applied: false))
        XCTAssertEqual(stages.formatting, .skipped)
    }

    func testFormattingFailedWhenAttemptedButNotApplied() {
        let stages = DictationStages(raw: "hi", cleanup: .recorded(nil), final: "hi",
                                     formatting: .init(attempted: true, applied: false))
        XCTAssertEqual(stages.formatting, .failed)
    }

    // The formatter's input is the cleaned text when cleanup ran, else the raw text.
    func testFormattingCountsChangedWordsAgainstItsInput() {
        let cleaned = DictationStages(raw: "um send it today", cleanup: .recorded("send it today"),
                                      final: "Send it today.", formatting: .init(attempted: true, applied: true))
        XCTAssertEqual(cleaned.formatting, .applied(changedWords: 2))

        let raw = DictationStages(raw: "send it today", cleanup: .recorded(nil),
                                  final: "Send it today.", formatting: .init(attempted: true, applied: true))
        XCTAssertEqual(raw.formatting, .applied(changedWords: 2))
    }

    func testFormattingInputIsTheCleanedTextOrRaw() {
        XCTAssertEqual(DictationStages.formatterInput(raw: "um hi", cleaned: "hi"), "hi")
        XCTAssertEqual(DictationStages.formatterInput(raw: "um hi", cleaned: nil), "um hi")
        XCTAssertNil(DictationStages.formatterInput(raw: nil, cleaned: nil))
    }
}
