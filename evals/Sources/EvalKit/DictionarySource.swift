import Foundation
import TalkToMyMacCore

/// Which dictionary to clean transcripts with.
public enum DictionaryChoice: Equatable, Sendable {
    /// The app's own dictionary: its folder's `dictionary.json` if one is set and readable,
    /// else the copy in its settings. The same order the app uses.
    case app
    /// A `dictionary.json` at this path.
    case file(String)
    /// No dictionary.
    case none
}

public struct ResolvedDictionary: Equatable, Sendable {
    public let entries: [DictionaryEntry]
    /// Where the entries came from, for the report.
    public let source: String
}

public enum DictionarySource {
    /// The app's bundle identifier, whose settings hold `dictionaryFolderPath` and `dictionaryJSON`.
    public static let appDefaultsDomain = "com.talktomymac.dictate"

    /// - Parameter loadFile: reads a `dictionary.json`, returning nil if it doesn't exist
    ///   (`DictionaryFile.load` in production).
    public static func resolve(_ choice: DictionaryChoice,
                               appFolderPath: String?,
                               appDefaultsJSON: String?,
                               loadFile: (URL) throws -> [DictionaryEntry]?) throws -> ResolvedDictionary {
        switch choice {
        case .none:
            return ResolvedDictionary(entries: [], source: "none")
        case .file(let path):
            guard let entries = try loadFile(URL(fileURLWithPath: path)) else {
                throw DictionarySourceError.fileNotFound(path)
            }
            return ResolvedDictionary(entries: entries, source: path)
        case .app:
            if let folder = appFolderPath {
                let url = DictionaryFile.url(in: URL(fileURLWithPath: folder))
                if let entries = try? loadFile(url) {
                    return ResolvedDictionary(entries: entries, source: "app folder: \(url.path)")
                }
            }
            if let json = appDefaultsJSON {
                return ResolvedDictionary(entries: try DictionaryEntry.parse(json), source: "app settings")
            }
            return ResolvedDictionary(entries: [], source: "none (the app has no dictionary)")
        }
    }
}

public enum DictionarySourceError: Error, CustomStringConvertible {
    case fileNotFound(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path): return "no dictionary at \(path)"
        }
    }
}
