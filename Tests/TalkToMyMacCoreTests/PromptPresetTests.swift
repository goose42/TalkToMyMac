import XCTest
@testable import TalkToMyMacCore

final class PromptPresetTests: XCTestCase {

    func testBuiltInPresetsHaveNonEmptyInstructions() {
        for preset in PromptPreset.allCases where preset != .custom {
            XCTAssertNotNil(preset.instructions, "\(preset) should have built-in instructions")
            XCTAssertFalse(preset.instructions!.isEmpty, "\(preset) instructions should not be empty")
        }
    }

    func testCustomPresetHasNoBuiltInInstructions() {
        XCTAssertNil(PromptPreset.custom.instructions)
    }

    func testDisplayNamesAreDistinct() {
        let names = PromptPreset.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count, "Display names should be unique")
    }

    func testAllCasesIncludesExpectedPresets() {
        XCTAssertEqual(
            Set(PromptPreset.allCases),
            [.coding, .cleanUp, .verbatim, .email, .codeComment, .custom]
        )
    }

    func testCodingIsTheDefaultAndListedFirst() {
        XCTAssertEqual(PromptPreset.default, .coding)
        XCTAssertEqual(PromptPreset.allCases.first, .coding)
    }

    /// The dictionary is applied deterministically before formatting, so no prompt mentions it.
    func testNoPresetMentionsTheDictionary() throws {
        for preset in PromptPreset.allCases where preset != .custom {
            let text = try XCTUnwrap(preset.instructions)
            XCTAssertFalse(text.lowercased().contains("dictionary"), "\(preset) should not mention the dictionary")
            XCTAssertFalse(text.contains("{{"), "\(preset) should have no template placeholders")
        }
    }

    func testCodingPresetContainsKeySections() throws {
        let text = try XCTUnwrap(PromptPreset.coding.instructions)
        for tag in ["<critical_rule>", "<output_format>", "<cleanup_rules>",
                    "<spoken_formatting>", "<examples>"] {
            XCTAssertTrue(text.contains(tag), "Coding prompt should contain \(tag)")
        }
        XCTAssertFalse(text.contains("{{TRANSCRIPT}}"), "The transcript belongs in the user turn")
    }

    /// The user turn is just the tagged transcript, so presets that don't say how to treat it
    /// must tell the model to output only the cleaned text.
    func testLegacyPresetsExplainTranscriptTagsAndOutput() throws {
        for preset in [PromptPreset.cleanUp, .verbatim, .email, .codeComment] {
            let text = try XCTUnwrap(preset.instructions)
            XCTAssertTrue(text.contains("<transcript>"), "\(preset) should mention the transcript tags")
            XCTAssertTrue(text.contains("Output only"), "\(preset) should restrict the output")
        }
    }

    // MARK: isEdited(_:)

    func testBuiltInTextIsNotEdited() {
        XCTAssertFalse(PromptPreset.email.isEdited(PromptPreset.email.instructions!))
    }

    func testChangedTextIsEdited() {
        XCTAssertTrue(PromptPreset.email.isEdited(PromptPreset.email.instructions! + " Sign off as Sam."))
        XCTAssertTrue(PromptPreset.email.isEdited(""))
    }

    // Custom has no built-in text, so anything typed counts as an edit.
    func testCustomIsEditedOnceItHasText() {
        XCTAssertFalse(PromptPreset.custom.isEdited(""))
        XCTAssertTrue(PromptPreset.custom.isEdited("Write in French."))
    }
}
