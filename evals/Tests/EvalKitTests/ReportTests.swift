import XCTest
@testable import EvalKit

final class ReportTests: XCTestCase {
    private func result(_ id: String, expected: String, actual: String?, judge: JudgeVerdict? = nil,
                        run: Int = 1) -> CaseResult {
        CaseResult(id: id, run: run, input: "in", formatterInput: "in", expected: expected,
                   actual: actual, error: actual == nil ? "timed out" : nil, judge: judge, seconds: 1)
    }

    func testExactMatchPasses() {
        XCTAssertTrue(result("a", expected: "Hi.", actual: "Hi.").passed)
    }

    func testJudgePassRescuesAnInexactOutput() {
        XCTAssertFalse(result("a", expected: "Hi.", actual: "Hello.").passed)
        XCTAssertTrue(result("a", expected: "Hi.", actual: "Hello.",
                             judge: JudgeVerdict(outcome: .pass, reason: "")).passed)
    }

    func testAFailedRunNeverPasses() {
        let failed = result("a", expected: "", actual: nil)
        XCTAssertFalse(failed.passed)
        XCTAssertEqual(failed.score.similarity, 0)
    }

    func testSummary() {
        let summary = Summary(results: [
            result("a", expected: "Hi.", actual: "Hi."),
            result("b", expected: "one two", actual: "one three"),
            result("c", expected: "x", actual: nil),
            result("d", expected: "y", actual: "z", judge: JudgeVerdict(outcome: .pass, reason: "")),
        ])
        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.passed, 2)
        XCTAssertEqual(summary.exact, 1)
        XCTAssertEqual(summary.errors, 1)
        XCTAssertEqual(summary.passRate, 0.5)
        XCTAssertEqual(summary.meanSimilarity, (1 + 0.5 + 0 + 0) / 4, accuracy: 0.0001)
    }

    func testTableListsEveryRunAndShowsFailures() {
        let table = Report.table([
            result("bullets", expected: "A.\n- b", actual: "A. - b"),
            result("simple", expected: "Hi.", actual: "Hi.", run: 2),
        ])
        XCTAssertTrue(table.contains("bullets"))
        XCTAssertTrue(table.contains("simple #2"))
        XCTAssertTrue(table.contains("expected: A.⏎- b"), table)
        XCTAssertTrue(table.contains("actual:   A. - b"), table)
    }

    func testReportEncodesAsJSON() throws {
        let report = EvalReport(suite: "coding", prompt: "built-in coding.md", dictionary: "none",
                                cleanup: true, judge: false, date: Date(timeIntervalSince1970: 0),
                                results: [result("a", expected: "Hi.", actual: "Hi.")])
        let json = String(decoding: try report.jsonData(), as: UTF8.self)
        XCTAssertTrue(json.contains("\"suite\" : \"coding\""), json)
        XCTAssertTrue(json.contains("\"passRate\" : 1"), json)
        XCTAssertTrue(json.contains("\"exactMatch\" : true"), json)
    }

    func testReportFileName() {
        let date = ISO8601DateFormatter().date(from: "2026-11-04T09:30:05Z")!
        XCTAssertEqual(Report.fileName(suite: "coding", date: date, timeZone: TimeZone(identifier: "UTC")!),
                       "coding-20261104-093005.json")
    }
}
