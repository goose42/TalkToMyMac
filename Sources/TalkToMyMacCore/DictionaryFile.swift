import Foundation

/// The dictionary as a file the user owns — `dictionary.json` in a folder they choose (e.g.
/// iCloud Drive) — plus parsing for files imported into it.
public enum DictionaryFile {
    public static let fileName = "dictionary.json"

    /// What an imported file holds: full entries (an exported dictionary) or bare words,
    /// one per line, whose details still need filling in.
    public enum ImportContents: Equatable, Sendable {
        case entries([DictionaryEntry])
        case words([String])
    }

    public static func url(in folder: URL) -> URL {
        folder.appendingPathComponent(fileName)
    }

    /// The file's entries, or nil if there's no file. Throws if it can't be read or parsed.
    public static func load(from url: URL) throws -> [DictionaryEntry]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try DictionaryEntry.parse(text)
    }

    /// Writes the entries atomically, creating the folder if needed.
    public static func save(_ entries: [DictionaryEntry], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data((DictionaryEntry.encode(entries) + "\n").utf8).write(to: url, options: .atomic)
    }

    /// Whether iCloud has evicted the file, leaving only its `.dictionary.json.icloud` placeholder.
    public static func isAwaitingICloudDownload(in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(".\(fileName).icloud").path)
    }

    /// `current` followed by the entries of `file` whose words it doesn't already have
    /// (ignoring case) — what you get when pointing the app at a folder that has a dictionary.
    public static func merge(current: [DictionaryEntry], file: [DictionaryEntry]) -> [DictionaryEntry] {
        var seen = Set(current.map { $0.written.lowercased() })
        return current + file.filter { seen.insert($0.written.lowercased()).inserted }
    }

    /// Reads an imported file: a JSON array is a dictionary (and must parse as one); anything
    /// else is one word or phrase per line, trimmed, without blanks or repeats ignoring case.
    public static func parseImport(_ text: String) throws(DictionaryParseError) -> ImportContents {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") {
            return .entries(try DictionaryEntry.parse(trimmed))
        }
        var seen = Set<String>()
        let words = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return .words(words)
    }
}
