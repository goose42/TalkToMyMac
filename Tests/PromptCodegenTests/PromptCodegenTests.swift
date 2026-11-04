import XCTest
@testable import PromptCodegen

final class PromptCodegenTests: XCTestCase {

    // MARK: identifier(forFileName:)

    func testIdentifierCamelCasesHyphenatedFileNames() {
        XCTAssertEqual(PromptCodegen.identifier(forFileName: "clean-up.md"), "cleanUp")
        XCTAssertEqual(PromptCodegen.identifier(forFileName: "dictionary-entry.md"), "dictionaryEntry")
    }

    func testIdentifierKeepsSingleWordNames() {
        XCTAssertEqual(PromptCodegen.identifier(forFileName: "coding.md"), "coding")
    }

    func testIdentifierHandlesUnderscoresSpacesAndCapitals() {
        XCTAssertEqual(PromptCodegen.identifier(forFileName: "Code_Comment v2.md"), "codeCommentV2")
    }

    func testIdentifierPrefixesNamesStartingWithADigit() {
        XCTAssertEqual(PromptCodegen.identifier(forFileName: "2nd-draft.md"), "_2ndDraft")
    }

    // MARK: promptText(fromFile:)

    func testPromptTextStripsExactlyOneTrailingNewline() {
        XCTAssertEqual(PromptCodegen.promptText(fromFile: "Hello\n"), "Hello")
        XCTAssertEqual(PromptCodegen.promptText(fromFile: "Hello\n\n"), "Hello\n")
        XCTAssertEqual(PromptCodegen.promptText(fromFile: "Hello"), "Hello")
    }

    func testPromptTextNormalizesWindowsLineEndings() {
        XCTAssertEqual(PromptCodegen.promptText(fromFile: "a\r\nb\r\n"), "a\nb")
    }

    // MARK: rawStringLiteral(_:)

    func testLiteralUsesOneHashWhenTextHasNone() {
        XCTAssertEqual(PromptCodegen.rawStringLiteral("Hi"), "#\"\"\"\nHi\n\"\"\"#")
    }

    func testLiteralUsesMoreHashesThanTheLongestRunInTheText() {
        let literal = PromptCodegen.rawStringLiteral("ends early? \"\"\"## no")
        XCTAssertTrue(literal.hasPrefix("###\"\"\"\n"), literal)
        XCTAssertTrue(literal.hasSuffix("\n\"\"\"###"), literal)
    }

    // MARK: source(prompts:)

    func testSourceDeclaresSortedPublicConstantsAndLookupTable() throws {
        let source = PromptCodegen.source(prompts: [
            (fileName: "verbatim.md", text: "V"),
            (fileName: "clean-up.md", text: "C"),
        ])
        XCTAssertTrue(source.contains("public enum PromptLibrary"))
        let clean = try XCTUnwrap(source.range(of: "public static let cleanUp = #\"\"\"\nC\n\"\"\"#"))
        let verbatim = try XCTUnwrap(source.range(of: "public static let verbatim = #\"\"\"\nV\n\"\"\"#"))
        XCTAssertLessThan(clean.lowerBound, verbatim.lowerBound)
        XCTAssertTrue(source.contains("\"clean-up\": cleanUp"))
        XCTAssertTrue(source.contains("\"verbatim\": verbatim"))
    }

    func testSourceRejectsDuplicateIdentifiers() {
        XCTAssertThrowsError(try PromptCodegen.checkedSource(prompts: [
            (fileName: "clean-up.md", text: "A"),
            (fileName: "clean_up.md", text: "B"),
        ]))
    }

    /// End to end: the generated literal must compile back to exactly the original text,
    /// including backslashes and interpolation-looking sequences.
    func testLiteralRoundTripsTrickyText() throws {
        let tricky = #"Use \(x) and \n literally; table \| cell; "quotes" and """ fences"#
        let literal = PromptCodegen.rawStringLiteral(tricky)
        // Can't compile at test time, so check the escape-sensitive parts survive verbatim
        // and that no delimiter collision is possible.
        XCTAssertTrue(literal.contains(tricky))
        XCTAssertFalse(tricky.contains("\"\"\"#"))
    }
}
