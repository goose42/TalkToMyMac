import Foundation

/// One term in the user's custom dictionary: something they say often that speech-to-text
/// tends to mis-hear (e.g. "OTel" transcribed as "hotel"). The dictionary is edited as JSON
/// and handed verbatim to the formatting model, so the field names are the JSON keys.
public struct DictionaryEntry: Equatable, Sendable {
    public enum EntryType: String, CaseIterable, Sendable {
        case noun
        case properNoun = "proper_noun"
        case verb
        case adjective
        case identifier
        case acronym
    }

    /// Exact output form, casing included.
    public var written: String
    public var type: EntryType
    /// Common mis-hearings the speech model produces for this term.
    public var soundsLike: [String]
    /// A few words on when the term applies, used to tell e.g. "rest" from `REST`.
    public var context: String?
    public var formatAsCode: Bool
    public var inflect: Bool

    public init(written: String, type: EntryType, soundsLike: [String] = [], context: String? = nil,
                formatAsCode: Bool = false, inflect: Bool = true) {
        self.written = written
        self.type = type
        self.soundsLike = soundsLike
        self.context = context
        self.formatAsCode = formatAsCode
        self.inflect = inflect
    }

    private enum Key {
        static let written = "written"
        static let type = "type"
        static let soundsLike = "sounds_like"
        static let context = "context"
        static let formatAsCode = "format_as_code"
        static let inflect = "inflect"
    }

    // MARK: Parsing

    /// Parses the dictionary's JSON text. Empty text is an empty dictionary. Throws a
    /// `DictionaryParseError` naming the first problem, with 1-based entry numbers.
    public static func parse(_ json: String) throws(DictionaryParseError) -> [DictionaryEntry] {
        guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: Data(json.utf8))
        } catch {
            throw DictionaryParseError.malformedJSON
        }
        guard let items = root as? [Any] else { throw DictionaryParseError.notAnArray }

        var entries: [DictionaryEntry] = []
        var seen = Set<String>()
        for (index, item) in items.enumerated() {
            let entry = try parseEntry(item, number: index + 1)
            guard seen.insert(entry.written.lowercased()).inserted else {
                throw DictionaryParseError.duplicate(written: entry.written)
            }
            entries.append(entry)
        }
        return entries
    }

    private static func parseEntry(_ item: Any, number: Int) throws(DictionaryParseError) -> DictionaryEntry {
        guard let object = item as? [String: Any] else { throw DictionaryParseError.notAnObject(entry: number) }

        func field<T>(_ key: String, as _: T.Type) throws(DictionaryParseError) -> T? {
            guard let value = object[key], !(value is NSNull) else { return nil }
            // JSONSerialization bridges booleans to NSNumber, which would also satisfy a
            // numeric cast; checking for Bool explicitly keeps `1` from passing as `true`.
            if T.self == Bool.self, CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID() {
                throw DictionaryParseError.wrongFieldType(entry: number, field: key)
            }
            guard let typed = value as? T else {
                throw DictionaryParseError.wrongFieldType(entry: number, field: key)
            }
            return typed
        }

        guard let rawWritten = try field(Key.written, as: String.self) else {
            throw DictionaryParseError.missingField(entry: number, field: Key.written)
        }
        let written = rawWritten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty else { throw DictionaryParseError.emptyWritten(entry: number) }

        guard let rawType = try field(Key.type, as: String.self) else {
            throw DictionaryParseError.missingField(entry: number, field: Key.type)
        }
        guard let type = EntryType(rawValue: rawType) else {
            throw DictionaryParseError.unknownType(entry: number, value: rawType)
        }

        return DictionaryEntry(
            written: written,
            type: type,
            soundsLike: try field(Key.soundsLike, as: [String].self) ?? [],
            context: try field(Key.context, as: String.self),
            formatAsCode: try field(Key.formatAsCode, as: Bool.self) ?? false,
            inflect: try field(Key.inflect, as: Bool.self) ?? true
        )
    }

    // MARK: Encoding

    /// Encodes entries as a JSON array, one entry per line, with `written` first and
    /// defaulted fields omitted — compact enough for the model's context window and still
    /// readable in the editor.
    public static func encode(_ entries: [DictionaryEntry]) -> String {
        guard !entries.isEmpty else { return "[]" }
        let lines = entries.map { entry -> String in
            var fields = [
                "\(quoted(Key.written)): \(quoted(entry.written))",
                "\(quoted(Key.type)): \(quoted(entry.type.rawValue))",
            ]
            if !entry.soundsLike.isEmpty {
                fields.append("\(quoted(Key.soundsLike)): [\(entry.soundsLike.map(quoted).joined(separator: ", "))]")
            }
            if let context = entry.context {
                fields.append("\(quoted(Key.context)): \(quoted(context))")
            }
            if entry.formatAsCode { fields.append("\(quoted(Key.formatAsCode)): true") }
            if !entry.inflect { fields.append("\(quoted(Key.inflect)): false") }
            return "  {" + fields.joined(separator: ", ") + "}"
        }
        return "[\n" + lines.joined(separator: ",\n") + "\n]"
    }

    /// A JSON string literal for `string`, with quotes, backslashes and control characters escaped.
    private static func quoted(_ string: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(string), let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }
}

/// Why the dictionary's JSON couldn't be used. Entry numbers are 1-based, as shown to the user.
public enum DictionaryParseError: Error, Equatable, CustomStringConvertible {
    case malformedJSON
    case notAnArray
    case notAnObject(entry: Int)
    case missingField(entry: Int, field: String)
    case wrongFieldType(entry: Int, field: String)
    case emptyWritten(entry: Int)
    case unknownType(entry: Int, value: String)
    case duplicate(written: String)

    public var description: String {
        switch self {
        case .malformedJSON:
            return "Not valid JSON — check for missing commas, quotes or brackets."
        case .notAnArray:
            return "The dictionary must be a JSON array: [ {…}, {…} ]."
        case .notAnObject(let entry):
            return "Entry \(entry) must be an object: {\"written\": …, \"type\": …}."
        case .missingField(let entry, let field):
            return "Entry \(entry) is missing \"\(field)\"."
        case .wrongFieldType(let entry, let field):
            return "Entry \(entry) has the wrong kind of value for \"\(field)\"."
        case .emptyWritten(let entry):
            return "Entry \(entry) has an empty \"written\"."
        case .unknownType(let entry, let value):
            let allowed = DictionaryEntry.EntryType.allCases.map(\.rawValue).joined(separator: ", ")
            return "Entry \(entry) has unknown type \"\(value)\" — use one of: \(allowed)."
        case .duplicate(let written):
            return "\"\(written)\" appears more than once."
        }
    }
}
