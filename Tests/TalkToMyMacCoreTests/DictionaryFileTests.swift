import XCTest
@testable import TalkToMyMacCore

final class DictionaryFileTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DictionaryFileTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let entries = [
        DictionaryEntry(written: "OTel", type: .acronym, soundsLike: ["hotel"]),
        DictionaryEntry(written: "kubectl", type: .identifier, formatAsCode: true),
    ]

    // MARK: Load and save

    func testFileLivesAtDictionaryJSONInFolder() {
        XCTAssertEqual(DictionaryFile.url(in: folder).lastPathComponent, "dictionary.json")
        XCTAssertEqual(DictionaryFile.url(in: folder).deletingLastPathComponent().path, folder.path)
    }

    func testSaveCreatesFolderAndRoundTrips() throws {
        let url = DictionaryFile.url(in: folder)
        try DictionaryFile.save(entries, to: url)
        XCTAssertEqual(try DictionaryFile.load(from: url), entries)
    }

    func testLoadMissingFileReturnsNil() throws {
        XCTAssertNil(try DictionaryFile.load(from: DictionaryFile.url(in: folder)))
    }

    func testLoadCorruptFileThrows() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = DictionaryFile.url(in: folder)
        try Data("[{\"written\": ".utf8).write(to: url)
        XCTAssertThrowsError(try DictionaryFile.load(from: url))
    }

    func testDetectsICloudPlaceholder() throws {
        XCTAssertFalse(DictionaryFile.isAwaitingICloudDownload(in: folder))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent(".dictionary.json.icloud"))
        XCTAssertTrue(DictionaryFile.isAwaitingICloudDownload(in: folder))
    }

    // MARK: Merging

    func testMergeKeepsCurrentEntriesAndAppendsNewOnesFromFile() {
        let current = [DictionaryEntry(written: "OTel", type: .acronym, context: "mine")]
        let file = [
            DictionaryEntry(written: "otel", type: .noun),
            DictionaryEntry(written: "REST", type: .acronym),
        ]
        XCTAssertEqual(DictionaryFile.merge(current: current, file: file), [
            DictionaryEntry(written: "OTel", type: .acronym, context: "mine"),
            DictionaryEntry(written: "REST", type: .acronym),
        ])
    }

    // MARK: Import parsing

    func testParseImportReadsDictionaryJSON() throws {
        XCTAssertEqual(try DictionaryFile.parseImport(DictionaryEntry.encode(entries)), .entries(entries))
    }

    func testParseImportReadsOneWordPerLine() throws {
        let text = "  OTel \n\nWispr Flow\r\notel\nkubectl\n"
        XCTAssertEqual(try DictionaryFile.parseImport(text), .words(["OTel", "Wispr Flow", "kubectl"]),
                       "Trimmed, blank lines dropped, duplicates ignoring case dropped")
    }

    func testParseImportSurfacesBadJSONInsteadOfReadingItAsWords() {
        XCTAssertThrowsError(try DictionaryFile.parseImport("  [{\"written\": \"OTel\"}]")) { error in
            XCTAssertEqual(error as? DictionaryParseError, .missingField(entry: 1, field: "type"))
        }
    }

    func testParseImportOfEmptyTextIsNoWords() throws {
        XCTAssertEqual(try DictionaryFile.parseImport(" \n "), .words([]))
    }
}
