import XCTest
@testable import EvalKit

final class EvalOptionsTests: XCTestCase {

    func testDefaults() throws {
        let options = try EvalOptions.parse(["cases/coding.jsonl"])
        XCTAssertEqual(options.casesPath, "cases/coding.jsonl")
        XCTAssertEqual(options.prompt, .suiteDefault)
        XCTAssertEqual(options.dictionary, .app)
        XCTAssertTrue(options.cleanup)
        XCTAssertFalse(options.judge)
        XCTAssertEqual(options.runs, 1)
        XCTAssertNil(options.threshold)
        XCTAssertNil(options.filter)
    }

    func testParsesEveryFlag() throws {
        let options = try EvalOptions.parse([
            "--prompt", "draft.md", "--dictionary", "d.json", "--no-cleanup", "--judge",
            "--runs", "3", "--threshold", "0.8", "--filter", "bullet", "cases/x.jsonl",
        ])
        XCTAssertEqual(options.prompt, .file("draft.md"))
        XCTAssertEqual(options.dictionary, .file("d.json"))
        XCTAssertFalse(options.cleanup)
        XCTAssertTrue(options.judge)
        XCTAssertEqual(options.runs, 3)
        XCTAssertEqual(options.threshold, 0.8)
        XCTAssertEqual(options.filter, "bullet")
    }

    func testPresetAndNoDictionary() throws {
        let options = try EvalOptions.parse(["--preset", "clean-up", "--no-dictionary", "c.jsonl"])
        XCTAssertEqual(options.prompt, .preset("clean-up"))
        XCTAssertEqual(options.dictionary, .none)
    }

    func testRejectsBadInput() {
        XCTAssertThrowsError(try EvalOptions.parse([]))
        XCTAssertThrowsError(try EvalOptions.parse(["--runs", "0", "c.jsonl"]))
        XCTAssertThrowsError(try EvalOptions.parse(["--threshold", "1.5", "c.jsonl"]))
        XCTAssertThrowsError(try EvalOptions.parse(["--prompt"]))
        XCTAssertThrowsError(try EvalOptions.parse(["--bogus", "c.jsonl"]))
        XCTAssertThrowsError(try EvalOptions.parse(["--preset", "a", "--prompt", "b.md", "c.jsonl"]))
    }

    func testHelp() {
        XCTAssertThrowsError(try EvalOptions.parse(["--help"])) { error in
            XCTAssertEqual(error as? EvalOptionsError, .helpRequested)
        }
    }
}
