import XCTest
import CryptoKit
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

    // MARK: Markdown prompts

    /// Built-in prompts are compiled from `Prompts/*.md`. Pinning their hashes guards
    /// `isEdited`: any byte change would flag every user's saved prompt as edited.
    /// Change a hash here only when you mean to change the prompt.
    func testCompiledPromptsMatchPinnedText() throws {
        let pinned: [(String, String)] = [
            (try XCTUnwrap(PromptPreset.coding.instructions), "39bcb6198805bf106ad0855c6b5f1cc45264ed29c0be40044f01f7e698346f79"),
            (try XCTUnwrap(PromptPreset.cleanUp.instructions), "a8fbbd47d1d5ad96f73b5d4045109c7f0cb301e260adc497a31d45df6b66a022"),
            (try XCTUnwrap(PromptPreset.verbatim.instructions), "c11860473bf90cc305ec9acdbfdd62ce1fbd4b7755a8016bf7ae1ba695689041"),
            (try XCTUnwrap(PromptPreset.email.instructions), "7b096fdb9496f8634ab5c38b0f3da4778216e8acc0e7af34315301550327c36c"),
            (try XCTUnwrap(PromptPreset.codeComment.instructions), "c470b745da9b037664ed67f86e41837aa4651249f23a908c8aa70ff32142eee9"),
            (DictionaryEntryPrompt.instructions, "6156351ffd2837147e34daf1c39dd895247a1c7bee7aa4e0ea680e5a6a9fb936"),
        ]
        for (index, (text, hash)) in pinned.enumerated() {
            let actual = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(actual, hash, "prompt #\(index) changed")
        }
    }

    func testPresetsReadFromThePromptLibrary() {
        XCTAssertEqual(PromptPreset.coding.instructions, PromptLibrary.coding)
        XCTAssertEqual(PromptPreset.cleanUp.instructions, PromptLibrary.cleanUp)
        XCTAssertEqual(PromptPreset.verbatim.instructions, PromptLibrary.verbatim)
        XCTAssertEqual(PromptPreset.email.instructions, PromptLibrary.email)
        XCTAssertEqual(PromptPreset.codeComment.instructions, PromptLibrary.codeComment)
        XCTAssertEqual(DictionaryEntryPrompt.instructions, PromptLibrary.dictionaryEntry)
    }

    func testPromptLibraryLooksUpByFileName() {
        XCTAssertEqual(PromptLibrary.all["clean-up"], PromptLibrary.cleanUp)
        XCTAssertEqual(PromptLibrary.all.count, 6)
    }

    func testPresetFileNameMatchesItsMarkdownFile() {
        XCTAssertEqual(PromptPreset.cleanUp.fileName, "clean-up")
        XCTAssertNil(PromptPreset.custom.fileName)
        for preset in PromptPreset.allCases where preset != .custom {
            XCTAssertEqual(PromptLibrary.all[preset.fileName!], preset.instructions)
        }
    }
}
