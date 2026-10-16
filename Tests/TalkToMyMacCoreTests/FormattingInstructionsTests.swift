import XCTest
@testable import TalkToMyMacCore

final class FormattingInstructionsTests: XCTestCase {

    // MARK: User turn

    func testUserPromptWrapsTranscriptInTags() {
        XCTAssertEqual(FormattingInstructions.userPrompt(transcript: "um hello there"),
                       "<transcript>\num hello there\n</transcript>")
    }
}
