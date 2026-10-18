import XCTest
@testable import TalkToMyMacCore

final class ShortDictationTests: XCTestCase {
    func testDropsTrailingPeriodAndLeadingCapital() {
        XCTAssertEqual(ShortDictation.apply("Sounds good."), "sounds good")
        XCTAssertEqual(ShortDictation.apply("Thanks."), "thanks")
    }

    func testLowercasesOnlyTheFirstLetter() {
        XCTAssertEqual(ShortDictation.apply("Call Sam."), "call Sam")
    }

    func testLeavesThreeWordsAlone() {
        XCTAssertEqual(ShortDictation.apply("Sounds good thanks."), "Sounds good thanks.")
    }

    func testKeepsOtherEndingPunctuation() {
        XCTAssertEqual(ShortDictation.apply("Really?"), "really?")
        XCTAssertEqual(ShortDictation.apply("Wow!"), "wow!")
        XCTAssertEqual(ShortDictation.apply("Well..."), "well...")
        XCTAssertEqual(ShortDictation.apply("Well…"), "well…")
    }

    func testKeepsIAndMixedCaseFirstWords() {
        XCTAssertEqual(ShortDictation.apply("OK."), "OK")
        XCTAssertEqual(ShortDictation.apply("I agree."), "I agree")
        XCTAssertEqual(ShortDictation.apply("I'm in."), "I'm in")
        XCTAssertEqual(ShortDictation.apply("I’m in."), "I’m in")
        XCTAssertEqual(ShortDictation.apply("iPhone."), "iPhone")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(ShortDictation.apply(""), "")
    }
}
