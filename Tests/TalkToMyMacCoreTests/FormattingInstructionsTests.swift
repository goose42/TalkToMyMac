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
}
