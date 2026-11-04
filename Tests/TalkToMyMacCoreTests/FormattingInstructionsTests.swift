import XCTest
@testable import TalkToMyMacCore

final class FormattingInstructionsTests: XCTestCase {

    // MARK: User turn

    func testUserPromptWrapsTranscriptInTags() {
        XCTAssertEqual(FormattingInstructions.userPrompt(transcript: "um hello there"),
                       "<transcript>\num hello there\n</transcript>")
    }

    // The on-device formatter prewarms with this prefix, so it must match what's sent.
    func testUserPromptStartsWithPrewarmPrefix() {
        XCTAssertTrue(FormattingInstructions.userPrompt(transcript: "hi")
            .hasPrefix(FormattingInstructions.userPromptPrefix))
    }

    // MARK: Generation settings

    // Shared by the on-device formatter and the evals so they can't drift apart.
    func testGenerationSettingsMatchTheAppsFormatter() {
        XCTAssertEqual(FormattingInstructions.temperature, 0.2)
        XCTAssertEqual(FormattingInstructions.maximumResponseTokens, 2048)
    }
}
