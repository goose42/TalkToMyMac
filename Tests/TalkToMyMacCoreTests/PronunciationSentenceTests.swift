import XCTest
@testable import TalkToMyMacCore

final class PronunciationSentenceTests: XCTestCase {

    func testDefaultSentenceWrapsTheWordInTheCarrier() {
        XCTAssertEqual(PronunciationSentence.defaultSentence(for: "OTel"), "I'm working with OTel today")
    }

    func testCustomTextIsUsedWhenPresent() {
        XCTAssertEqual(
            PronunciationSentence.resolve(custom: "We deploy OTel on Fridays", default: "I'm working with OTel today"),
            "We deploy OTel on Fridays")
    }

    func testCustomTextIsTrimmed() {
        XCTAssertEqual(
            PronunciationSentence.resolve(custom: "  Use OTel here \n", default: "fallback"),
            "Use OTel here")
    }

    func testEmptyCustomTextFallsBackToDefault() {
        XCTAssertEqual(PronunciationSentence.resolve(custom: "", default: "fallback"), "fallback")
    }

    func testWhitespaceOnlyCustomTextFallsBackToDefault() {
        XCTAssertEqual(PronunciationSentence.resolve(custom: " \n\t ", default: "fallback"), "fallback")
    }

    func testNilCustomTextFallsBackToDefault() {
        XCTAssertEqual(PronunciationSentence.resolve(custom: nil, default: "fallback"), "fallback")
    }

    func testCarrierSplitsAroundTheWord() {
        let carrier = PronunciationSentence.carrier(in: "We deploy OTel on Fridays", around: "OTel")
        XCTAssertEqual(carrier?.prefix, "We deploy")
        XCTAssertEqual(carrier?.suffix, "on Fridays")
    }

    func testCarrierIgnoresCaseAndAllowsEmptyEnds() {
        let carrier = PronunciationSentence.carrier(in: "otel rocks", around: "OTel")
        XCTAssertEqual(carrier?.prefix, "")
        XCTAssertEqual(carrier?.suffix, "rocks")
    }

    func testCarrierIsNilWhenTheWordIsMissing() {
        XCTAssertNil(PronunciationSentence.carrier(in: "Nothing here", around: "OTel"))
    }

    func testSlotExtractionUsesACustomCarrier() {
        XCTAssertEqual(
            PronunciationProbe.extractSlot(from: "We deploy hotel on Fridays", prefix: "We deploy", suffix: "on Fridays"),
            "hotel")
    }
}
