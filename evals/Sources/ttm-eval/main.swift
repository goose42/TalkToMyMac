import EvalKit
import Foundation
import FoundationModels
import TalkToMyMacCore

// Runs a formatting prompt over a case file the way the app does: deterministic cleanup with
// the dictionary, then Apple's on-device model with the app's guardrails and settings. Then
// scores each output against the expected text. All decisions live in EvalKit; this file only
// does I/O and model calls.

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("ttm-eval: \(message)\n".utf8))
    exit(code)
}

let options: EvalOptions
do {
    options = try EvalOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch .helpRequested {
    print(EvalOptions.usage)
    exit(0)
} catch {
    fail("\(error)\n\n\(EvalOptions.usage)", code: 64)
}

// MARK: Inputs

let suite = EvalCase.suiteName(forPath: options.casesPath)
let cases: [EvalCase]
let prompt: ResolvedPrompt
let dictionary: ResolvedDictionary
do {
    let text = try String(contentsOfFile: options.casesPath, encoding: .utf8)
    cases = try EvalCase.parseJSONL(text).filter { case_ in
        options.filter.map { case_.id.contains($0) } ?? true
    }
    prompt = try PromptSource.resolve(options.prompt, suiteName: suite, library: PromptLibrary.all) {
        try String(contentsOfFile: $0, encoding: .utf8)
    }
    let appDefaults = UserDefaults(suiteName: DictionarySource.appDefaultsDomain)
    dictionary = try DictionarySource.resolve(
        options.dictionary,
        appFolderPath: appDefaults?.string(forKey: "dictionaryFolderPath"),
        appDefaultsJSON: appDefaults?.string(forKey: "dictionaryJSON"),
        loadFile: { try DictionaryFile.load(from: $0) }
    )
} catch {
    fail("\(options.casesPath): \(error)")
}
guard !cases.isEmpty else { fail("no cases to run") }

// The same model and guardrails as the app's FoundationModelFormatter.
let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
guard case .available = model.availability else {
    fail("the on-device model isn't available: \(model.availability)", code: 2)
}

print("suite:      \(suite) (\(cases.count) cases × \(options.runs) runs)")
print("prompt:     \(prompt.source)")
print("dictionary: \(dictionary.source) (\(dictionary.entries.count) entries)")
print("cleanup:    \(options.cleanup ? "on" : "off")\(options.judge ? " · judge on" : "")")
print("")

// MARK: Model calls

/// Races a model call against a timeout so one hung case doesn't stall the suite.
func respond(_ session: LanguageModelSession, to text: String, options: GenerationOptions,
             timeout: Duration = .seconds(30)) async -> Result<String, Error> {
    struct TimedOut: Error, CustomStringConvertible { var description: String { "timed out" } }
    return await withTaskGroup(of: Result<String, Error>?.self) { group in
        group.addTask {
            do { return .success(try await session.respond(to: text, options: options).content) }
            catch { return .failure(error) }
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return Task.isCancelled ? nil : .failure(TimedOut())
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first ?? .failure(TimedOut())
    }
}

let formattingOptions = GenerationOptions(temperature: FormattingInstructions.temperature,
                                          maximumResponseTokens: FormattingInstructions.maximumResponseTokens)

var results: [CaseResult] = []
for case_ in cases {
    // Cleaned text is what the app hands the formatter; nil means cleanup changed nothing.
    let formatterInput = DeterministicCleanup.clean(case_.input, dictionary: dictionary.entries,
                                                    fullCleanup: options.cleanup && case_.runsCleanup,
                                                    language: nil) ?? case_.input
    for run in 1...options.runs {
        let start = ContinuousClock.now
        // A fresh session per case, as the app uses one per dictation.
        let session = LanguageModelSession(model: model, instructions: prompt.text)
        let reply = await respond(session, to: FormattingInstructions.userPrompt(transcript: formatterInput),
                                  options: formattingOptions)
        let elapsed = ContinuousClock.now - start
        let actual = try? reply.get().trimmingCharacters(in: .whitespacesAndNewlines)
        let error = actual == nil ? reply.failureDescription : nil

        var judge: JudgeVerdict?
        if options.judge, let actual, Score(expected: case_.expected, actual: actual).exactMatch == false {
            let judgeSession = LanguageModelSession(model: model, instructions: JudgePrompt.instructions)
            let verdict = await respond(judgeSession,
                                        to: JudgePrompt.prompt(input: case_.input, expected: case_.expected, actual: actual),
                                        options: GenerationOptions(temperature: 0))
            judge = (try? verdict.get()).map(JudgeVerdict.init(reply:))
                ?? JudgeVerdict(outcome: .unknown, reason: verdict.failureDescription ?? "")
        }

        let result = CaseResult(id: case_.id, run: run, input: case_.input, formatterInput: formatterInput,
                                expected: case_.expected, actual: actual, error: error, judge: judge,
                                seconds: Double(elapsed.components.seconds)
                                    + Double(elapsed.components.attoseconds) / 1e18)
        results.append(result)
        print(result.passed ? "." : "F", terminator: "")
        fflush(stdout)
    }
}
print("\n")

// MARK: Report

let report = EvalReport(suite: suite, prompt: prompt.source, dictionary: dictionary.source,
                        cleanup: options.cleanup, judge: options.judge, date: Date(), results: results)
print(Report.table(results))
print("")
print(Report.summaryLine(report.summary))

let casesDirectory = URL(fileURLWithPath: options.casesPath).deletingLastPathComponent()
let resultsDirectory = (casesDirectory.lastPathComponent == "cases"
    ? casesDirectory.deletingLastPathComponent() : casesDirectory).appendingPathComponent("results")
do {
    try FileManager.default.createDirectory(at: resultsDirectory, withIntermediateDirectories: true)
    let url = resultsDirectory.appendingPathComponent(Report.fileName(suite: suite, date: report.date))
    try report.jsonData().write(to: url)
    print("report:     \(url.path)")
} catch {
    fail("couldn't write the report: \(error)")
}

if let threshold = options.threshold, report.summary.passRate < threshold {
    fail(String(format: "pass rate %.0f%% is below the %.0f%% threshold",
                report.summary.passRate * 100, threshold * 100))
}

extension Result {
    var failureDescription: String? {
        if case .failure(let error) = self { return "\(error)" }
        return nil
    }
}
