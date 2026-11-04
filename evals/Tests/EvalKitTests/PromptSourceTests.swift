import XCTest
@testable import EvalKit

final class PromptSourceTests: XCTestCase {
    private let library = ["coding": "C", "clean-up": "U"]

    private func resolve(_ choice: PromptChoice, suite: String = "coding",
                         files: [String: String] = [:]) throws -> ResolvedPrompt {
        try PromptSource.resolve(choice, suiteName: suite, library: library) { path in
            guard let text = files[path] else { throw CocoaError(.fileNoSuchFile) }
            return text
        }
    }

    func testSuiteDefaultUsesThePromptNamedLikeTheCaseFile() throws {
        XCTAssertEqual(try resolve(.suiteDefault, suite: "clean-up"),
                       ResolvedPrompt(text: "U", source: "built-in clean-up.md"))
    }

    func testSuiteWithoutAMatchingPromptThrows() {
        XCTAssertThrowsError(try resolve(.suiteDefault, suite: "mine")) { error in
            XCTAssertTrue("\(error)".contains("clean-up, coding"), "\(error)")
        }
    }

    func testPreset() throws {
        XCTAssertEqual(try resolve(.preset("coding"), suite: "other").text, "C")
        XCTAssertThrowsError(try resolve(.preset("nope")))
    }

    /// A draft file is read the way the compiler reads prompts: minus one trailing newline.
    func testDraftFile() throws {
        XCTAssertEqual(try resolve(.file("d.md"), files: ["d.md": "Draft\n"]),
                       ResolvedPrompt(text: "Draft", source: "d.md"))
    }
}
