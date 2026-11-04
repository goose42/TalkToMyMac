import Foundation

/// One eval case: a raw transcript and the text you want the prompt to turn it into.
/// Case files are JSON Lines, one case per line; blank lines and `//` comments are skipped.
public struct EvalCase: Codable, Equatable, Sendable {
    public let id: String
    /// The transcript as speech-to-text would produce it.
    public let input: String
    /// The text you want delivered.
    public let expected: String
    /// Why the case exists; shown in reports only.
    public let notes: String?
    /// Whether deterministic cleanup (with the dictionary) runs before the model, as it does
    /// in the app when cleanup is on. Defaults to on.
    public let cleanup: Bool?

    public init(id: String, input: String, expected: String, notes: String? = nil, cleanup: Bool? = nil) {
        self.id = id
        self.input = input
        self.expected = expected
        self.notes = notes
        self.cleanup = cleanup
    }

    public var runsCleanup: Bool { cleanup ?? true }

    public static func parseJSONL(_ text: String) throws(EvalCaseError) -> [EvalCase] {
        var cases: [EvalCase] = []
        var seen = Set<String>()
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("//") else { continue }
            let number = index + 1
            let evalCase: EvalCase
            do {
                evalCase = try JSONDecoder().decode(EvalCase.self, from: Data(line.utf8))
            } catch {
                throw .invalidLine(number: number, reason: describe(error))
            }
            guard seen.insert(evalCase.id).inserted else { throw .duplicateID(evalCase.id, line: number) }
            cases.append(evalCase)
        }
        return cases
    }

    /// `cases/clean-up.jsonl` → `clean-up`.
    public static func suiteName(forPath path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _):
            return "missing field \"\(key.stringValue)\""
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            let field = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "wrong type for \"\(field)\""
        default:
            return "not valid JSON"
        }
    }
}

public enum EvalCaseError: Error, Equatable, CustomStringConvertible {
    case invalidLine(number: Int, reason: String)
    case duplicateID(String, line: Int)

    public var description: String {
        switch self {
        case let .invalidLine(number, reason): return "line \(number): \(reason)"
        case let .duplicateID(id, line):       return "line \(line): duplicate id \"\(id)\""
        }
    }
}
