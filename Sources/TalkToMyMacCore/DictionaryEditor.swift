import Foundation
import Observation

/// Editing state for the custom dictionary behind the Settings tab. Adding a word creates a
/// bare entry and asks the generator to fill in the rest; the user can edit any field at any
/// time, and an edit made while a suggestion is pending wins over that suggestion.
@MainActor
@Observable
public final class DictionaryEditor {
    public enum Status: Equatable, Sendable {
        case ready
        case generating
        case generationFailed
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var entry: DictionaryEntry
        public var status: Status
    }

    public private(set) var items: [Item]
    public var entries: [DictionaryEntry] { items.map(\.entry) }
    public var canGenerate: Bool { generator != nil }

    /// In-flight generation per item, exposed for tests to await.
    @ObservationIgnored private(set) var generationTasks: [UUID: Task<Void, Never>] = [:]
    /// The most recently queued request; the next one waits for it.
    @ObservationIgnored private var lastGenerationTask: Task<Void, Never>?
    /// The request whose result an item is waiting for. A result is applied only if its
    /// token still matches — an edit or a newer request clears or replaces it.
    @ObservationIgnored private var pendingRequests: [UUID: UUID] = [:]
    @ObservationIgnored private let generator: DictionaryEntryGenerating?
    @ObservationIgnored private let onChange: ([DictionaryEntry]) -> Void

    public static let maxSoundsLike = 5

    public init(entries: [DictionaryEntry], generator: DictionaryEntryGenerating?,
                onChange: @escaping ([DictionaryEntry]) -> Void) {
        self.items = entries.map { Item(id: UUID(), entry: $0, status: .ready) }
        self.generator = generator
        self.onChange = onChange
    }

    public func item(_ id: UUID) -> Item? {
        items.first { $0.id == id }
    }

    /// Adds `word` as a new entry and starts generating its other fields. Returns the new
    /// item's id, or nil if the word is empty or already in the dictionary.
    @discardableResult
    public func add(_ word: String) -> UUID? {
        let written = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty, !isTaken(written, by: nil) else { return nil }
        let item = Item(id: UUID(), entry: DictionaryEntry(written: written, type: .noun), status: .ready)
        items.append(item)
        save()
        startGeneration(for: item.id)
        return item.id
    }

    /// Replaces an entry with the user's edit. Rejected (returns false) if `written` would
    /// be empty or clash with another entry. Cancels any pending suggestion for the item.
    @discardableResult
    public func update(_ id: UUID, to entry: DictionaryEntry) -> Bool {
        guard let index = index(of: id) else { return false }
        var entry = entry
        entry.written = entry.written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.written.isEmpty, !isTaken(entry.written, by: id) else { return false }

        cancelGeneration(for: id)
        items[index].entry = entry
        items[index].status = .ready
        save()
        return true
    }

    /// Appends heard-as forms the entry doesn't have yet (ignoring case, and skipping the
    /// written form), e.g. ones learned from a recording. Counts as an edit, so it wins over
    /// a pending suggestion. Returns the forms actually added; saves only if there were any.
    @discardableResult
    public func addSoundsLike(_ forms: [String], to id: UUID) -> [String] {
        guard let index = index(of: id) else { return [] }
        var entry = items[index].entry
        var seen = Set(([entry.written] + entry.soundsLike).map { $0.lowercased() })
        let added = forms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        guard !added.isEmpty else { return [] }

        entry.soundsLike += added
        update(id, to: entry)
        return added
    }

    public func remove(_ id: UUID) {
        cancelGeneration(for: id)
        items.removeAll { $0.id == id }
        save()
    }

    /// Asks the generator again, replacing the item's fields (except `written`) when it answers.
    public func regenerate(_ id: UUID) {
        startGeneration(for: id)
    }

    public struct ImportResult: Equatable, Sendable {
        public var added: Int
        /// Words already in the dictionary, or repeated in the import, ignoring case.
        public var skipped: Int
    }

    /// Adds what the file holds, skipping words already present. Imported entries are kept
    /// as they are; bare words are queued for generation. Saves once, if anything was added.
    @discardableResult
    public func `import`(_ contents: DictionaryFile.ImportContents) -> ImportResult {
        let (candidates, generate): ([DictionaryEntry], Bool)
        switch contents {
        case .entries(let entries):
            (candidates, generate) = (entries, false)
        case .words(let words):
            (candidates, generate) = (words.map { DictionaryEntry(written: $0, type: .noun) }, true)
        }

        var result = ImportResult(added: 0, skipped: 0)
        var addedIDs: [UUID] = []
        for var entry in candidates {
            entry.written = entry.written.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.written.isEmpty else { continue }
            guard !isTaken(entry.written, by: nil) else {
                result.skipped += 1
                continue
            }
            let item = Item(id: UUID(), entry: entry, status: .ready)
            items.append(item)
            addedIDs.append(item.id)
            result.added += 1
        }
        guard result.added > 0 else { return result }

        save()
        if generate {
            addedIDs.forEach(startGeneration)
        }
        return result
    }

    /// Replaces every entry, e.g. with the contents of the dictionary file. Doesn't save:
    /// the caller already holds these entries. Pending suggestions are dropped.
    public func replaceAll(_ entries: [DictionaryEntry]) {
        pendingRequests.removeAll()
        items = entries.map { Item(id: UUID(), entry: $0, status: .ready) }
    }

    // MARK: Generation

    /// Queues a request for the item. Requests run one at a time, in order — the on-device
    /// model handles one well, and an import can queue a hundred. A request whose token has
    /// been cleared or replaced by the time its turn comes (the user edited or removed the
    /// item, or asked again) is skipped without calling the generator.
    private func startGeneration(for id: UUID) {
        guard let generator, let index = index(of: id) else { return }
        let token = UUID()
        let written = items[index].entry.written
        pendingRequests[id] = token
        items[index].status = .generating

        let previous = lastGenerationTask
        let task = Task { [weak self] in
            await previous?.value
            guard self?.pendingRequests[id] == token else { return }
            let suggestion = await generator.suggestEntry(for: written)
            self?.finishGeneration(for: id, token: token, suggestion: suggestion)
        }
        generationTasks[id] = task
        lastGenerationTask = task
    }

    private func finishGeneration(for id: UUID, token: UUID, suggestion: DictionaryEntry?) {
        guard pendingRequests[id] == token, let index = index(of: id) else { return }
        pendingRequests[id] = nil

        guard let suggestion else {
            items[index].status = .generationFailed
            return
        }
        items[index].entry = Self.sanitized(suggestion, written: items[index].entry.written)
        items[index].status = .ready
        save()
    }

    private func cancelGeneration(for id: UUID) {
        pendingRequests[id] = nil
    }

    /// Keeps the user's spelling and tidies the model's lists: trimmed, no empties, no exact
    /// copy of the written form, unique ignoring case, at most `maxSoundsLike`.
    static func sanitized(_ suggestion: DictionaryEntry, written: String) -> DictionaryEntry {
        var seen = Set<String>()
        let soundsLike = suggestion.soundsLike
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != written && seen.insert($0.lowercased()).inserted }
        let context = suggestion.context?.trimmingCharacters(in: .whitespacesAndNewlines)

        var entry = suggestion
        entry.written = written
        entry.soundsLike = Array(soundsLike.prefix(maxSoundsLike))
        entry.context = (context?.isEmpty ?? true) ? nil : context
        return entry
    }

    // MARK: Helpers

    private func index(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    private func isTaken(_ written: String, by id: UUID?) -> Bool {
        items.contains { $0.id != id && $0.entry.written.caseInsensitiveCompare(written) == .orderedSame }
    }

    private func save() {
        onChange(entries)
    }
}
