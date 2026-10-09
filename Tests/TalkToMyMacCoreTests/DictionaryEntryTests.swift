import XCTest
@testable import TalkToMyMacCore

final class DictionaryEntryTests: XCTestCase {

    private func parseError(_ json: String, file: StaticString = #filePath, line: UInt = #line) -> DictionaryParseError? {
        do {
            _ = try DictionaryEntry.parse(json)
            XCTFail("Expected a parse error", file: file, line: line)
            return nil
        } catch let error as DictionaryParseError {
            return error
        } catch {
            XCTFail("Unexpected error type: \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: Parsing

    func testParsesFullEntry() throws {
        let json = """
        [{"written": "useEffect", "type": "identifier", "sounds_like": ["use effect", "use a fact"],
          "context": "React hooks, components", "format_as_code": true, "inflect": false}]
        """
        let entries = try DictionaryEntry.parse(json)
        XCTAssertEqual(entries, [DictionaryEntry(
            written: "useEffect", type: .identifier, soundsLike: ["use effect", "use a fact"],
            context: "React hooks, components", formatAsCode: true, inflect: false
        )])
    }

    func testOptionalFieldsDefault() throws {
        let entries = try DictionaryEntry.parse(#"[{"written": "OTel", "type": "acronym"}]"#)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.soundsLike, [])
        XCTAssertNil(entry.context)
        XCTAssertFalse(entry.formatAsCode)
        XCTAssertTrue(entry.inflect)
    }

    func testParsesEveryType() throws {
        for type in DictionaryEntry.EntryType.allCases {
            let entries = try DictionaryEntry.parse(#"[{"written": "x", "type": "\#(type.rawValue)"}]"#)
            XCTAssertEqual(entries.first?.type, type)
        }
        XCTAssertEqual(DictionaryEntry.EntryType.properNoun.rawValue, "proper_noun")
    }

    func testEmptyTextParsesToNoEntries() throws {
        XCTAssertEqual(try DictionaryEntry.parse(""), [])
        XCTAssertEqual(try DictionaryEntry.parse("  \n "), [])
        XCTAssertEqual(try DictionaryEntry.parse("[]"), [])
    }

    func testTrimsWrittenValue() throws {
        let entries = try DictionaryEntry.parse(#"[{"written": "  OTel ", "type": "acronym"}]"#)
        XCTAssertEqual(entries.first?.written, "OTel")
    }

    func testMalformedJSONThrows() {
        XCTAssertEqual(parseError("[{"), .malformedJSON)
    }

    func testTopLevelObjectThrows() {
        XCTAssertEqual(parseError(#"{"written": "OTel", "type": "acronym"}"#), .notAnArray)
    }

    func testNonObjectEntryThrows() {
        XCTAssertEqual(parseError(#"["OTel"]"#), .notAnObject(entry: 1))
    }

    func testMissingWrittenThrows() {
        XCTAssertEqual(parseError(#"[{"type": "noun"}]"#), .missingField(entry: 1, field: "written"))
    }

    func testMissingTypeThrows() {
        XCTAssertEqual(parseError(#"[{"written": "OTel"}]"#), .missingField(entry: 1, field: "type"))
    }

    func testEmptyWrittenThrows() {
        XCTAssertEqual(parseError(#"[{"written": "  ", "type": "noun"}]"#), .emptyWritten(entry: 1))
    }

    func testUnknownTypeThrowsWithEntryNumber() {
        let json = #"[{"written": "a", "type": "noun"}, {"written": "b", "type": "thing"}]"#
        XCTAssertEqual(parseError(json), .unknownType(entry: 2, value: "thing"))
    }

    func testWrongFieldTypeThrows() {
        XCTAssertEqual(parseError(#"[{"written": "a", "type": "noun", "sounds_like": "ay"}]"#),
                       .wrongFieldType(entry: 1, field: "sounds_like"))
        XCTAssertEqual(parseError(#"[{"written": "a", "type": "noun", "format_as_code": "yes"}]"#),
                       .wrongFieldType(entry: 1, field: "format_as_code"))
    }

    func testDuplicateWrittenThrowsIgnoringCase() {
        let json = #"[{"written": "OTel", "type": "acronym"}, {"written": "otel", "type": "noun"}]"#
        XCTAssertEqual(parseError(json), .duplicate(written: "otel"))
    }

    func testErrorDescriptionsNameTheEntry() {
        XCTAssertTrue(DictionaryParseError.unknownType(entry: 2, value: "thing").description.contains("2"))
        XCTAssertTrue(DictionaryParseError.unknownType(entry: 2, value: "thing").description.contains("thing"))
        XCTAssertTrue(DictionaryParseError.missingField(entry: 3, field: "written").description.contains("written"))
    }

    // MARK: Encoding

    func testEncodeRoundTrips() throws {
        let entries = [
            DictionaryEntry(written: "OTel", type: .acronym, soundsLike: ["hotel", "oh tel"],
                            context: "appears next to words like collector, tracing"),
            DictionaryEntry(written: "useEffect", type: .identifier, soundsLike: ["use effect"], formatAsCode: true),
            DictionaryEntry(written: "dedupe", type: .verb, inflect: false),
            DictionaryEntry(written: #"say "hi"\"#, type: .noun),
        ]
        XCTAssertEqual(try DictionaryEntry.parse(DictionaryEntry.encode(entries)), entries)
    }

    func testEncodeUsesSnakeCaseKeys() {
        let json = DictionaryEntry.encode([DictionaryEntry(
            written: "useEffect", type: .identifier, soundsLike: ["use effect"], formatAsCode: true
        )])
        XCTAssertTrue(json.contains(#""sounds_like""#))
        XCTAssertTrue(json.contains(#""format_as_code""#))
    }

    func testEncodeOmitsDefaultedFields() {
        let json = DictionaryEntry.encode([DictionaryEntry(written: "OTel", type: .acronym)])
        XCTAssertFalse(json.contains("sounds_like"))
        XCTAssertFalse(json.contains("context"))
        XCTAssertFalse(json.contains("format_as_code"))
        XCTAssertFalse(json.contains("inflect"))
    }

    func testEncodeListsWrittenFirst() throws {
        let json = DictionaryEntry.encode([DictionaryEntry(written: "OTel", type: .acronym, context: "tracing")])
        let written = try XCTUnwrap(json.range(of: "written")).lowerBound
        let type = try XCTUnwrap(json.range(of: "type")).lowerBound
        XCTAssertLessThan(written, type)
    }

    func testEncodeEmptyIsEmptyArray() {
        XCTAssertEqual(DictionaryEntry.encode([]), "[]")
    }
}
