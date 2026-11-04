import XCTest
@testable import EvalKit

final class EvalCaseTests: XCTestCase {

    func testParsesOneCasePerLine() throws {
        let cases = try EvalCase.parseJSONL("""
        {"id": "a", "input": "um hi", "expected": "Hi."}
        {"id": "b", "input": "new line", "expected": "x\\ny", "notes": "bullets", "cleanup": false}
        """)
        XCTAssertEqual(cases, [
            EvalCase(id: "a", input: "um hi", expected: "Hi."),
            EvalCase(id: "b", input: "new line", expected: "x\ny", notes: "bullets", cleanup: false),
        ])
    }

    func testSkipsBlankLinesAndComments() throws {
        let cases = try EvalCase.parseJSONL("""

        // Self-corrections
        {"id": "a", "input": "x", "expected": "X."}

        """)
        XCTAssertEqual(cases.map(\.id), ["a"])
    }

    func testReportsTheLineNumberOfInvalidJSON() {
        XCTAssertThrowsError(try EvalCase.parseJSONL("""
        {"id": "a", "input": "x", "expected": "X."}
        {"id": "b", "input": "x"
        """)) { error in
            guard case let EvalCaseError.invalidLine(number, _) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(number, 2)
        }
    }

    func testRejectsAMissingField() {
        XCTAssertThrowsError(try EvalCase.parseJSONL(#"{"id": "a", "input": "x"}"#)) { error in
            guard case EvalCaseError.invalidLine(1, let reason) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(reason.contains("expected"), reason)
        }
    }

    func testRejectsDuplicateIDs() {
        XCTAssertThrowsError(try EvalCase.parseJSONL("""
        {"id": "a", "input": "x", "expected": "X."}
        {"id": "a", "input": "y", "expected": "Y."}
        """)) { error in
            XCTAssertEqual(error as? EvalCaseError, .duplicateID("a", line: 2))
        }
    }

    func testCleanupDefaultsToOn() throws {
        let cases = try EvalCase.parseJSONL(#"{"id": "a", "input": "x", "expected": "X."}"#)
        XCTAssertTrue(cases[0].runsCleanup)
    }

    func testSuiteNameIsTheFileStem() {
        XCTAssertEqual(EvalCase.suiteName(forPath: "evals/cases/clean-up.jsonl"), "clean-up")
    }
}
