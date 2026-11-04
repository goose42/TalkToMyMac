import XCTest
import TalkToMyMacCore
@testable import EvalKit

final class DictionarySourceTests: XCTestCase {
    private let fileEntries = [DictionaryEntry(written: "useState", type: .identifier, soundsLike: ["use state"])]
    private let defaultsJSON = DictionaryEntry.encode([DictionaryEntry(written: "Groq", type: .properNoun)])

    private func resolve(_ choice: DictionaryChoice,
                         folder: String? = nil,
                         defaults: String? = nil,
                         files: [String: [DictionaryEntry]] = [:]) throws -> ResolvedDictionary {
        try DictionarySource.resolve(choice, appFolderPath: folder, appDefaultsJSON: defaults) { url in
            files[url.path]
        }
    }

    func testNoDictionaryWins() throws {
        let resolved = try resolve(.none, folder: "/f", defaults: defaultsJSON,
                                   files: ["/f/dictionary.json": fileEntries])
        XCTAssertEqual(resolved.entries, [])
        XCTAssertEqual(resolved.source, "none")
    }

    func testExplicitFile() throws {
        let resolved = try resolve(.file("/tmp/d.json"), defaults: defaultsJSON,
                                   files: ["/tmp/d.json": fileEntries])
        XCTAssertEqual(resolved.entries, fileEntries)
        XCTAssertEqual(resolved.source, "/tmp/d.json")
    }

    func testMissingExplicitFileThrows() {
        XCTAssertThrowsError(try resolve(.file("/nope.json")))
    }

    func testAppFolderFileBeatsDefaults() throws {
        let resolved = try resolve(.app, folder: "/f", defaults: defaultsJSON,
                                   files: ["/f/dictionary.json": fileEntries])
        XCTAssertEqual(resolved.entries, fileEntries)
        XCTAssertEqual(resolved.source, "app folder: /f/dictionary.json")
    }

    func testFallsBackToAppDefaults() throws {
        let resolved = try resolve(.app, folder: "/f", defaults: defaultsJSON)
        XCTAssertEqual(resolved.entries.map(\.written), ["Groq"])
        XCTAssertEqual(resolved.source, "app settings")
    }

    func testNoAppDictionaryIsEmpty() throws {
        let resolved = try resolve(.app)
        XCTAssertEqual(resolved.entries, [])
        XCTAssertEqual(resolved.source, "none (the app has no dictionary)")
    }
}
