import XCTest
@testable import TalkToMyMacCore

final class FormattingInstructionsTests: XCTestCase {

    private let base = "You are a dictation post-processor."
    private let entries = [
        DictionaryEntry(written: "OTel", type: .acronym, soundsLike: ["hotel"], context: "OpenTelemetry, tracing"),
        DictionaryEntry(written: "useEffect", type: .identifier, formatAsCode: true),
    ]

    // MARK: Placeholder substitution

    func testPlaceholderReplacedWithDictionaryJSON() {
        let template = "Rules.\n<dictionary>\n{{DICTIONARY}}\n</dictionary>\nMore rules."
        let result = FormattingInstructions.compose(base: template, dictionary: entries)
        XCTAssertFalse(result.contains(FormattingInstructions.dictionaryPlaceholder))
        XCTAssertEqual(result, template.replacingOccurrences(
            of: "{{DICTIONARY}}", with: DictionaryEntry.encode(entries)))
    }

    func testPlaceholderWithEmptyDictionaryBecomesEmptyArray() {
        let template = "<dictionary>\n{{DICTIONARY}}\n</dictionary>"
        XCTAssertEqual(FormattingInstructions.compose(base: template, dictionary: []),
                       "<dictionary>\n[]\n</dictionary>")
    }

    func testPlaceholderConstant() {
        XCTAssertEqual(FormattingInstructions.dictionaryPlaceholder, "{{DICTIONARY}}")
    }

    // MARK: Prompts without the placeholder

    func testEmptyDictionaryReturnsBaseUnchanged() {
        XCTAssertEqual(FormattingInstructions.compose(base: base, dictionary: []), base)
    }

    func testDictionaryAppendedAfterBaseWhenNoPlaceholder() {
        let result = FormattingInstructions.compose(base: base, dictionary: entries)
        XCTAssertTrue(result.hasPrefix(base + "\n\n"))
        XCTAssertTrue(result.contains("<dictionary>\n" + DictionaryEntry.encode(entries) + "\n</dictionary>"))
        XCTAssertTrue(result.contains("sounds_like"), "Appended rules should explain the entry fields")
    }

    func testEveryWrittenFormAppearsVerbatim() {
        let result = FormattingInstructions.compose(base: base, dictionary: entries)
        XCTAssertTrue(result.contains("OTel"))
        XCTAssertTrue(result.contains("useEffect"))
    }

    // MARK: User turn

    func testUserPromptWrapsTranscriptInTags() {
        XCTAssertEqual(FormattingInstructions.userPrompt(transcript: "um hello there"),
                       "<transcript>\num hello there\n</transcript>")
    }
}
