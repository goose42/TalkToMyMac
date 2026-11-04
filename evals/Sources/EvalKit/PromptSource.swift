import Foundation
import PromptCodegen

/// Which system prompt to evaluate.
public enum PromptChoice: Equatable, Sendable {
    /// The built-in prompt named like the case file (`cases/coding.jsonl` → `coding.md`).
    case suiteDefault
    /// A built-in prompt by file name, e.g. `clean-up`.
    case preset(String)
    /// A Markdown file on disk, e.g. a draft you haven't compiled into the app yet.
    case file(String)
}

public struct ResolvedPrompt: Equatable, Sendable {
    public let text: String
    /// Where the prompt came from, for the report.
    public let source: String
}

public enum PromptSource {
    /// - Parameters:
    ///   - library: built-in prompts keyed by file name (`PromptLibrary.all` in production).
    ///   - readFile: reads a file's contents.
    public static func resolve(_ choice: PromptChoice,
                               suiteName: String,
                               library: [String: String],
                               readFile: (String) throws -> String) throws -> ResolvedPrompt {
        switch choice {
        case .suiteDefault:
            return try builtIn(suiteName, library: library)
        case .preset(let name):
            return try builtIn(name, library: library)
        case .file(let path):
            return ResolvedPrompt(text: PromptCodegen.promptText(fromFile: try readFile(path)), source: path)
        }
    }

    private static func builtIn(_ name: String, library: [String: String]) throws -> ResolvedPrompt {
        guard let text = library[name] else {
            throw PromptSourceError.unknownPrompt(name, available: library.keys.sorted())
        }
        return ResolvedPrompt(text: text, source: "built-in \(name).md")
    }
}

public enum PromptSourceError: Error, CustomStringConvertible {
    case unknownPrompt(String, available: [String])

    public var description: String {
        switch self {
        case let .unknownPrompt(name, available):
            return "no built-in prompt named \"\(name)\" (available: \(available.joined(separator: ", "))); "
                + "pass --preset or --prompt"
        }
    }
}
