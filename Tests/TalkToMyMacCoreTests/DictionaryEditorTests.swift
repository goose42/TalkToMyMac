import XCTest
@testable import TalkToMyMacCore

// MARK: - Mocks

/// Returns a canned suggestion only when the test releases one, so tests control whether
/// the user's edits land before or after generation finishes.
final class GatedEntryGenerator: DictionaryEntryGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [String] = []
    private let stream: AsyncStream<DictionaryEntry?>
    private let continuation: AsyncStream<DictionaryEntry?>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: DictionaryEntry?.self)
    }

    var requested: [String] { lock.withLock { _requested } }

    func release(_ suggestion: DictionaryEntry?) { continuation.yield(suggestion) }

    func suggestEntry(for written: String) async -> DictionaryEntry? {
        lock.withLock { _requested.append(written) }
        for await suggestion in stream { return suggestion }
        return nil
    }
}

// MARK: - Tests

@MainActor
final class DictionaryEditorTests: XCTestCase {

    private var saved: [[DictionaryEntry]] = []
    private let otelSuggestion = DictionaryEntry(
        written: "ignored", type: .acronym, soundsLike: ["hotel", "oh tel"],
        context: "appears next to words like collector, tracing"
    )

    private func makeEditor(entries: [DictionaryEntry] = [],
                            generator: DictionaryEntryGenerating? = nil) -> DictionaryEditor {
        DictionaryEditor(entries: entries, generator: generator) { [weak self] in self?.saved.append($0) }
    }

    // MARK: Loading

    func testInitLoadsEntriesAsReadyItems() {
        let editor = makeEditor(entries: [DictionaryEntry(written: "OTel", type: .acronym)])
        XCTAssertEqual(editor.entries, [DictionaryEntry(written: "OTel", type: .acronym)])
        XCTAssertEqual(editor.items.map(\.status), [.ready])
        XCTAssertTrue(saved.isEmpty, "Loading shouldn't trigger a save")
    }

    // MARK: Adding

    func testAddWithoutGeneratorAppendsReadyNounEntry() throws {
        let editor = makeEditor()
        let id = try XCTUnwrap(editor.add("  OTel "))
        XCTAssertEqual(editor.item(id)?.entry, DictionaryEntry(written: "OTel", type: .noun))
        XCTAssertEqual(editor.item(id)?.status, .ready)
        XCTAssertEqual(saved.last, [DictionaryEntry(written: "OTel", type: .noun)])
    }

    func testAddRejectsEmptyAndDuplicateWords() {
        let editor = makeEditor(entries: [DictionaryEntry(written: "OTel", type: .acronym)])
        XCTAssertNil(editor.add("   "))
        XCTAssertNil(editor.add("otel"))
        XCTAssertEqual(editor.entries.count, 1)
        XCTAssertTrue(saved.isEmpty)
    }

    func testAddWithGeneratorStartsGeneratingWithTrimmedWord() async throws {
        let generator = GatedEntryGenerator()
        let editor = makeEditor(generator: generator)
        let id = try XCTUnwrap(editor.add(" OTel "))
        XCTAssertEqual(editor.item(id)?.status, .generating)

        generator.release(nil)
        await editor.generationTasks[id]?.value
        XCTAssertEqual(generator.requested, ["OTel"])
    }

    func testGeneratedSuggestionFillsFieldsButKeepsTheUsersWord() async throws {
        let generator = GatedEntryGenerator()
        let editor = makeEditor(generator: generator)
        let id = try XCTUnwrap(editor.add("OTel"))

        generator.release(otelSuggestion)
        await editor.generationTasks[id]?.value

        let item = try XCTUnwrap(editor.item(id))
        XCTAssertEqual(item.status, .ready)
        XCTAssertEqual(item.entry, DictionaryEntry(
            written: "OTel", type: .acronym, soundsLike: ["hotel", "oh tel"],
            context: "appears next to words like collector, tracing"
        ))
        XCTAssertEqual(saved.last, [item.entry])
    }

    func testFailedGenerationMarksItemAndKeepsEntry() async throws {
        let generator = GatedEntryGenerator()
        let editor = makeEditor(generator: generator)
        let id = try XCTUnwrap(editor.add("OTel"))

        generator.release(nil)
        await editor.generationTasks[id]?.value

        XCTAssertEqual(editor.item(id)?.status, .generationFailed)
        XCTAssertEqual(editor.item(id)?.entry, DictionaryEntry(written: "OTel", type: .noun))
    }

    func testSuggestionIsSanitized() async throws {
        let generator = GatedEntryGenerator()
        let editor = makeEditor(generator: generator)
        let id = try XCTUnwrap(editor.add("REST"))

        generator.release(DictionaryEntry(
            written: "REST", type: .acronym,
            soundsLike: [" rest ", "REST", "", "Rest", "rest", "wrest", "r e s t", "ressed", "rust", "roost"],
            context: "   "
        ))
        await editor.generationTasks[id]?.value

        let entry = try XCTUnwrap(editor.item(id)?.entry)
        XCTAssertEqual(entry.soundsLike, ["rest", "wrest", "r e s t", "ressed", "rust"],
                       "Trimmed, empties and the exact written form dropped, de-duplicated ignoring case, capped at 5")
        XCTAssertNil(entry.context, "A blank context becomes nil")
    }

    // MARK: Editing

    func testUserEditDuringGenerationWins() async throws {
        let generator = GatedEntryGenerator()
        let editor = makeEditor(generator: generator)
        let id = try XCTUnwrap(editor.add("OTel"))

        let edited = DictionaryEntry(written: "OTel", type: .properNoun, context: "mine")
        XCTAssertTrue(editor.update(id, to: edited))
        XCTAssertEqual(editor.item(id)?.status, .ready, "Editing stops waiting for the model")

        generator.release(otelSuggestion)
        await editor.generationTasks[id]?.value
        XCTAssertEqual(editor.item(id)?.entry, edited, "A late suggestion must not overwrite the user's edit")
    }

    func testUpdateTrimsWrittenAndSaves() throws {
        let editor = makeEditor(entries: [DictionaryEntry(written: "Otel", type: .noun)])
        let id = try XCTUnwrap(editor.items.first?.id)
        XCTAssertTrue(editor.update(id, to: DictionaryEntry(written: " OTel ", type: .acronym)))
        XCTAssertEqual(editor.entries, [DictionaryEntry(written: "OTel", type: .acronym)])
        XCTAssertEqual(saved.last, editor.entries)
    }

    func testUpdateRejectsEmptyOrDuplicateWritten() throws {
        let editor = makeEditor(entries: [
            DictionaryEntry(written: "OTel", type: .acronym),
            DictionaryEntry(written: "REST", type: .acronym),
        ])
        let restID = editor.items[1].id
        XCTAssertFalse(editor.update(restID, to: DictionaryEntry(written: "  ", type: .acronym)))
        XCTAssertFalse(editor.update(restID, to: DictionaryEntry(written: "otel", type: .acronym)))
        XCTAssertEqual(editor.entries[1].written, "REST")
        XCTAssertTrue(saved.isEmpty)
    }

    func testUpdateAllowsChangingCaseOfItsOwnWord() throws {
        let editor = makeEditor(entries: [DictionaryEntry(written: "Otel", type: .noun)])
        let id = editor.items[0].id
        XCTAssertTrue(editor.update(id, to: DictionaryEntry(written: "OTel", type: .noun)))
    }

    func testRemoveDeletesAndSaves() throws {
        let editor = makeEditor(entries: [
            DictionaryEntry(written: "OTel", type: .acronym),
            DictionaryEntry(written: "REST", type: .acronym),
        ])
        editor.remove(editor.items[0].id)
        XCTAssertEqual(editor.entries.map(\.written), ["REST"])
        XCTAssertEqual(saved.last, editor.entries)
    }

    // MARK: Regenerating

    func testRegenerateReplacesFieldsEvenAfterEdits() async throws {
        let generator = GatedEntryGenerator()
        let editor = makeEditor(entries: [DictionaryEntry(written: "OTel", type: .noun, context: "old")],
                                generator: generator)
        let id = editor.items[0].id

        editor.regenerate(id)
        XCTAssertEqual(editor.item(id)?.status, .generating)
        generator.release(otelSuggestion)
        await editor.generationTasks[id]?.value

        XCTAssertEqual(editor.item(id)?.entry.type, .acronym)
        XCTAssertEqual(editor.item(id)?.entry.context, "appears next to words like collector, tracing")
        XCTAssertEqual(editor.item(id)?.entry.written, "OTel")
    }

    func testRegenerateWithoutGeneratorDoesNothing() {
        let editor = makeEditor(entries: [DictionaryEntry(written: "OTel", type: .noun)])
        editor.regenerate(editor.items[0].id)
        XCTAssertEqual(editor.items[0].status, .ready)
        XCTAssertFalse(editor.canGenerate)
    }
}
