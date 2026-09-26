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
            [.cleanUp, .verbatim, .email, .codeComment, .custom]
        )
    }
}
