import Foundation

/// Command-line options for `ttm-eval`.
public struct EvalOptions: Equatable, Sendable {
    public var casesPath: String
    public var prompt: PromptChoice = .suiteDefault
    public var dictionary: DictionaryChoice = .app
    public var cleanup = true
    public var judge = false
    public var runs = 1
    /// The minimum pass rate (0–1); below it the tool exits non-zero.
    public var threshold: Double?
    /// Only cases whose id contains this.
    public var filter: String?

    public static let usage = """
    usage: ttm-eval <cases.jsonl> [options]

      --preset <name>       built-in prompt to test (default: the one named like the case file)
      --prompt <file.md>    test a prompt file instead, e.g. a draft
      --dictionary <file>   clean transcripts with this dictionary.json (default: the app's)
      --no-dictionary       clean transcripts without a dictionary
      --no-cleanup          send transcripts to the model without deterministic cleanup
      --judge               ask the on-device model whether inexact outputs are acceptable
      --runs <n>            run each case n times (default 1)
      --threshold <0-1>     exit 1 if the pass rate is below this
      --filter <text>       only cases whose id contains this
    """

    public static func parse(_ arguments: [String]) throws(EvalOptionsError) -> EvalOptions {
        var casesPath: String?
        var options = EvalOptions(casesPath: "")
        var promptSet = false
        var dictionarySet = false
        var remaining = arguments[...]

        func value(for flag: String) throws(EvalOptionsError) -> String {
            guard let value = remaining.popFirst(), !value.hasPrefix("--") else { throw .missingValue(flag) }
            return value
        }
        func setPrompt(_ choice: PromptChoice) throws(EvalOptionsError) {
            guard !promptSet else { throw .conflicting("--preset", "--prompt") }
            promptSet = true
            options.prompt = choice
        }
        func setDictionary(_ choice: DictionaryChoice) throws(EvalOptionsError) {
            guard !dictionarySet else { throw .conflicting("--dictionary", "--no-dictionary") }
            dictionarySet = true
            options.dictionary = choice
        }

        while let argument = remaining.popFirst() {
            switch argument {
            case "-h", "--help":   throw .helpRequested
            case "--preset":       try setPrompt(.preset(try value(for: argument)))
            case "--prompt":       try setPrompt(.file(try value(for: argument)))
            case "--dictionary":   try setDictionary(.file(try value(for: argument)))
            case "--no-dictionary": try setDictionary(.none)
            case "--no-cleanup":   options.cleanup = false
            case "--judge":        options.judge = true
            case "--filter":       options.filter = try value(for: argument)
            case "--runs":
                guard let runs = Int(try value(for: argument)), runs > 0 else { throw .invalidValue("--runs") }
                options.runs = runs
            case "--threshold":
                guard let threshold = Double(try value(for: argument)), (0...1).contains(threshold) else {
                    throw .invalidValue("--threshold")
                }
                options.threshold = threshold
            default:
                guard !argument.hasPrefix("-") else { throw .unknownFlag(argument) }
                guard casesPath == nil else { throw .extraArgument(argument) }
                casesPath = argument
            }
        }
        guard let casesPath else { throw .missingCasesFile }
        options.casesPath = casesPath
        return options
    }
}

public enum EvalOptionsError: Error, Equatable, CustomStringConvertible {
    case helpRequested
    case missingCasesFile
    case missingValue(String)
    case invalidValue(String)
    case unknownFlag(String)
    case extraArgument(String)
    case conflicting(String, String)

    public var description: String {
        switch self {
        case .helpRequested:          return EvalOptions.usage
        case .missingCasesFile:       return "missing the cases file"
        case .missingValue(let flag): return "\(flag) needs a value"
        case .invalidValue(let flag): return "invalid value for \(flag)"
        case .unknownFlag(let flag):  return "unknown option \(flag)"
        case .extraArgument(let arg): return "unexpected argument \(arg)"
        case let .conflicting(a, b):  return "use only one of \(a) and \(b)"
        }
    }
}
