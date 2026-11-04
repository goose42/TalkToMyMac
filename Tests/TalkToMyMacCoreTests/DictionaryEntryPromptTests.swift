import XCTest
@testable import TalkToMyMacCore

final class DictionaryEntryPromptTests: XCTestCase {

    func testPromptContainsTheWord() {
        XCTAssertTrue(DictionaryEntryPrompt.prompt(for: "OTel").contains("OTel"))
    }

    func testInstructionsDescribeEveryType() {
        for type in DictionaryEntry.EntryType.allCases {
            XCTAssertTrue(DictionaryEntryPrompt.instructions.contains(type.rawValue), "Missing \(type.rawValue)")
        }
    }

    func testInstructionsForbidTheTermInNeighbourWords() {
        XCTAssertTrue(DictionaryEntryPrompt.instructions.contains("Never include the term itself"))
    }

    // MARK: Building an entry from the model's answer

    /// The formatting model copies words out of `context` into its output, so context
    /// describes where the term appears, built from neighbouring words rather than prose.
    func testContextBuiltFromNeighbourWords() {
        let entry = DictionaryEntryPrompt.entry(
            written: "OTel", type: .acronym,
            neighborWords: [" collector ", "tracing", "", "spans"], formatAsCode: false, inflect: true)
        XCTAssertEqual(entry.context, "appears next to words like collector, tracing, spans")
    }

    func testNeighbourWordsMatchingTheTermAreDropped() {
        let entry = DictionaryEntryPrompt.entry(
            written: "OTel", type: .acronym,
            neighborWords: ["otel", "OTel collector", "tracing"], formatAsCode: false, inflect: true)
        XCTAssertEqual(entry.context, "appears next to words like tracing")
    }

    func testNoUsableNeighbourWordsMeansNoContext() {
        let entry = DictionaryEntryPrompt.entry(
            written: "OTel", type: .acronym, neighborWords: [" ", "OTel"],
            formatAsCode: false, inflect: true)
        XCTAssertNil(entry.context)
    }

    func testFormatAsCodeOnlyForIdentifiers() {
        XCTAssertTrue(DictionaryEntryPrompt.entry(
            written: "useEffect", type: .identifier, neighborWords: [],
            formatAsCode: true, inflect: true).formatAsCode)
        XCTAssertFalse(DictionaryEntryPrompt.entry(
            written: "OTel", type: .acronym, neighborWords: [],
            formatAsCode: true, inflect: true).formatAsCode)
    }

    func testInflectCanOnlyBeDisabledForVerbs() {
        XCTAssertFalse(DictionaryEntryPrompt.entry(
            written: "dedupe", type: .verb, neighborWords: [],
            formatAsCode: false, inflect: false).inflect)
        XCTAssertTrue(DictionaryEntryPrompt.entry(
            written: "OTel", type: .acronym, neighborWords: [],
            formatAsCode: false, inflect: false).inflect)
    }

    func testEntryKeepsWrittenAndType() {
        let entry = DictionaryEntryPrompt.entry(
            written: "useEffect", type: .identifier, neighborWords: [],
            formatAsCode: true, inflect: true)
        XCTAssertEqual(entry.written, "useEffect")
        XCTAssertEqual(entry.type, .identifier)
        XCTAssertEqual(entry.soundsLike, [])
    }

    func testInstructionsDoNotAskTheModelToGuessSoundAlikes() {
        XCTAssertFalse(DictionaryEntryPrompt.instructions.contains("soundsLike"))
    }

    func testListParsingSplitsOnCommasAndTrims() {
        XCTAssertEqual(DictionaryEntry.parseList(" hotel, oh tel ,, o tell "), ["hotel", "oh tel", "o tell"])
        XCTAssertEqual(DictionaryEntry.parseList(""), [])
    }

    func testListFormattingJoinsWithCommas() {
        XCTAssertEqual(DictionaryEntry.formatList(["hotel", "oh tel"]), "hotel, oh tel")
    }
}
