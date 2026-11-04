import XCTest
@testable import EvalKit

final class JudgeVerdictTests: XCTestCase {

    func testParsesPassWithReason() {
        XCTAssertEqual(JudgeVerdict(reply: "PASS: same meaning, only a comma differs"),
                       JudgeVerdict(outcome: .pass, reason: "same meaning, only a comma differs"))
    }

    func testParsesFailOnItsOwnLine() {
        XCTAssertEqual(JudgeVerdict(reply: "FAIL\nThe self-correction was not resolved."),
                       JudgeVerdict(outcome: .fail, reason: "The self-correction was not resolved."))
    }

    func testIgnoresCaseAndMarkdown() {
        XCTAssertEqual(JudgeVerdict(reply: "**pass** - fine").outcome, .pass)
        XCTAssertEqual(JudgeVerdict(reply: "  Fail. Missing bullet").outcome, .fail)
    }

    func testAnythingElseIsUnknown() {
        let verdict = JudgeVerdict(reply: "I think they are similar")
        XCTAssertEqual(verdict.outcome, .unknown)
        XCTAssertEqual(verdict.reason, "I think they are similar")
    }

    /// "Passable" or "failure" shouldn't count; only the verdict word does.
    func testRequiresTheWholeWord() {
        XCTAssertEqual(JudgeVerdict(reply: "Passable output").outcome, .unknown)
    }

    func testJudgePromptIncludesAllThreeTexts() {
        let prompt = JudgePrompt.prompt(input: "um hi", expected: "Hi.", actual: "Hello.")
        XCTAssertTrue(prompt.contains("<input>\num hi\n</input>"))
        XCTAssertTrue(prompt.contains("<expected>\nHi.\n</expected>"))
        XCTAssertTrue(prompt.contains("<actual>\nHello.\n</actual>"))
        XCTAssertTrue(JudgePrompt.instructions.contains("PASS"))
        XCTAssertTrue(JudgePrompt.instructions.contains("FAIL"))
    }
}
