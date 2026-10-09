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

    // MARK: Importing

    func testImportEntriesKeepsTheirFieldsAndSkipsDuplicates() {
        let generator = GatedEntryGenerator()
        let editor = makeEditor(entries: [DictionaryEntry(written: "OTel", type: .acronym)], generator: generator)
        let rest = DictionaryEntry(written: "REST", type: .acronym, soundsLike: ["rest"], context: "API")

        let result = editor.import(.entries([
            DictionaryEntry(written: "otel", type: .noun),
            rest,
            DictionaryEntry(written: "rest", type: .noun),
        ]))

        XCTAssertEqual(result, DictionaryEditor.ImportResult(added: 1, skipped: 2))
        XCTAssertEqual(editor.entries, [DictionaryEntry(written: "OTel", type: .acronym), rest])
        XCTAssertEqual(editor.items.map(\.status), [.ready, .ready], "Imported entries already have details")
        XCTAssertTrue(generator.requested.isEmpty)
        XCTAssertEqual(saved, [editor.entries], "One save for the whole import")
    }

    func testImportWordsAddsBareEntriesAndQueuesGeneration() async throws {
        let generator = GatedEntryGenerator()
        let editor = makeEditor(entries: [DictionaryEntry(written: "OTel", type: .acronym)], generator: generator)

        let result = editor.import(.words(["otel", " REST ", "", "Wispr Flow"]))

        XCTAssertEqual(result, DictionaryEditor.ImportResult(added: 2, skipped: 1))
        XCTAssertEqual(editor.entries.map(\.written), ["OTel", "REST", "Wispr Flow"])
        XCTAssertEqual(editor.items.map(\.status), [.ready, .generating, .generating])
        XCTAssertEqual(saved.count, 1)

        generator.release(nil)
        generator.release(nil)
        await editor.generationTasks[editor.items[2].id]?.value
        XCTAssertEqual(generator.requested, ["REST", "Wispr Flow"], "Generated in import order")
    }

    func testImportOfNothingNewDoesNotSave() {
        let editor = makeEditor(entries: [DictionaryEntry(written: "OTel", type: .acronym)])
        XCTAssertEqual(editor.import(.words(["OTEL"])), DictionaryEditor.ImportResult(added: 0, skipped: 1))
        XCTAssertTrue(saved.isEmpty)
    }

    // MARK: Generation queue

    func testGenerationRunsOneWordAtATime() async throws {
        let generator = ConcurrencyTrackingGenerator()
        let editor = makeEditor(generator: generator)
        editor.import(.words(["a", "b", "c", "d"]))

        for item in editor.items { await editor.generationTasks[item.id]?.value }
        XCTAssertEqual(generator.requested, ["a", "b", "c", "d"])
        XCTAssertEqual(generator.maxInFlight, 1)
    }

    func testRemovingAQueuedWordSkipsItsGeneration() async throws {
        let generator = GatedEntryGenerator()
        let editor = makeEditor(generator: generator)
        editor.import(.words(["a", "b", "c"]))
        let b = editor.items[1].id
        let c = editor.items[2].id

        editor.remove(b)
        generator.release(nil)
        generator.release(nil)
        await editor.generationTasks[c]?.value
        XCTAssertEqual(generator.requested, ["a", "c"])
    }

    func testEditingAQueuedWordSkipsItsGeneration() async throws {
        let generator = GatedEntryGenerator()
        let editor = makeEditor(generator: generator)
        editor.import(.words(["a", "b"]))
        let b = editor.items[1].id

        XCTAssertTrue(editor.update(b, to: DictionaryEntry(written: "b", type: .verb)))
        XCTAssertEqual(editor.item(b)?.status, .ready)
        generator.release(nil)
        await editor.generationTasks[b]?.value
        XCTAssertEqual(generator.requested, ["a"])
        XCTAssertEqual(editor.item(b)?.entry.type, .verb)
    }

    // MARK: Replacing

    func testReplaceAllSwapsEntriesWithoutSavingAndDropsPendingGeneration() async throws {
        let generator = GatedEntryGenerator()
        let editor = makeEditor(generator: generator)
        let old = try XCTUnwrap(editor.add("OTel"))
        saved.removeAll()

        editor.replaceAll([DictionaryEntry(written: "REST", type: .acronym)])
        XCTAssertEqual(editor.entries, [DictionaryEntry(written: "REST", type: .acronym)])
        XCTAssertEqual(editor.items.map(\.status), [.ready])
        XCTAssertTrue(saved.isEmpty, "The caller already has these entries")

        generator.release(otelSuggestion)
        await editor.generationTasks[old]?.value
        XCTAssertEqual(editor.entries, [DictionaryEntry(written: "REST", type: .acronym)])
    }
}

/// Answers after a short delay, recording how many requests overlapped.
final class ConcurrencyTrackingGenerator: DictionaryEntryGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [String] = []
    private var inFlight = 0
    private var _maxInFlight = 0

    var requested: [String] { lock.withLock { _requested } }
    var maxInFlight: Int { lock.withLock { _maxInFlight } }

    func suggestEntry(for written: String) async -> DictionaryEntry? {
        lock.withLock {
            _requested.append(written)
            inFlight += 1
            _maxInFlight = max(_maxInFlight, inFlight)
        }
        try? await Task.sleep(for: .milliseconds(10))
        lock.withLock { inFlight -= 1 }
        return nil
    }
}
