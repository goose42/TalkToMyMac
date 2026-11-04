import Foundation

/// One run of one case.
public struct CaseResult: Codable, Equatable, Sendable {
    public let id: String
    /// 1-based, for `--runs`.
    public let run: Int
    public let input: String
    /// What the model was given: the input after deterministic cleanup, if it ran.
    public let formatterInput: String
    public let expected: String
    /// The model's output, or nil if it failed.
    public let actual: String?
    public let error: String?
    public let judge: JudgeVerdict?
    public let seconds: Double
    public let score: Score

    public init(id: String, run: Int, input: String, formatterInput: String, expected: String,
                actual: String?, error: String?, judge: JudgeVerdict?, seconds: Double) {
        self.id = id
        self.run = run
        self.input = input
        self.formatterInput = formatterInput
        self.expected = expected
        self.actual = actual
        self.error = error
        self.judge = judge
        self.seconds = seconds
        score = actual.map { Score(expected: expected, actual: $0) } ?? .failed
    }

    /// An exact match, or an output the judge accepted.
    public var passed: Bool {
        actual != nil && (score.exactMatch || judge?.outcome == .pass)
    }
}

public struct Summary: Codable, Equatable, Sendable {
    public let total: Int
    public let passed: Int
    public let exact: Int
    public let errors: Int
    public let passRate: Double
    public let meanSimilarity: Double

    public init(results: [CaseResult]) {
        total = results.count
        passed = results.filter(\.passed).count
        exact = results.filter { $0.actual != nil && $0.score.exactMatch }.count
        errors = results.filter { $0.actual == nil }.count
        passRate = total == 0 ? 0 : Double(passed) / Double(total)
        meanSimilarity = total == 0 ? 0 : results.map(\.score.similarity).reduce(0, +) / Double(total)
    }
}

/// Everything about one eval run, written to `evals/results/` as JSON.
public struct EvalReport: Codable, Sendable {
    public let suite: String
    public let prompt: String
    public let dictionary: String
    public let cleanup: Bool
    public let judge: Bool
    public let date: Date
    public let summary: Summary
    public let results: [CaseResult]

    public init(suite: String, prompt: String, dictionary: String, cleanup: Bool, judge: Bool,
                date: Date, results: [CaseResult]) {
        self.suite = suite
        self.prompt = prompt
        self.dictionary = dictionary
        self.cleanup = cleanup
        self.judge = judge
        self.date = date
        self.results = results
        summary = Summary(results: results)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

public enum Report {
    /// A plain-text table: one row per run, with expected and actual text under each miss.
    public static func table(_ results: [CaseResult]) -> String {
        let showRun = results.contains { $0.run > 1 }
        let names = results.map { showRun ? "\($0.id) #\($0.run)" : $0.id }
        let width = max(4, names.map(\.count).max() ?? 0)
        var lines = ["\(pad("case", width))  result  exact  sim   judge    time"]
        for (result, name) in zip(results, names) {
            let verdict = result.passed ? "PASS" : result.actual == nil ? "ERROR" : "FAIL"
            let exact = result.score.exactMatch ? "yes" : "no"
            let similarity = String(format: "%.2f", result.score.similarity)
            let judge = result.judge?.outcome.rawValue ?? "-"
            let time = String(format: "%.1fs", result.seconds)
            lines.append("\(pad(name, width))  \(pad(verdict, 6))  \(pad(exact, 5))  \(similarity)  \(pad(judge, 7))  \(time)")
            guard !result.passed else { continue }
            lines.append("    expected: \(oneLine(result.expected))")
            lines.append("    actual:   \(result.actual.map(oneLine) ?? "(\(result.error ?? "no output"))")")
            if let judge = result.judge, !judge.reason.isEmpty {
                lines.append("    judge:    \(oneLine(judge.reason))")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func summaryLine(_ summary: Summary) -> String {
        String(format: "%d/%d passed (%.0f%%) · %d exact · mean similarity %.2f · %d errors",
               summary.passed, summary.total, summary.passRate * 100, summary.exact,
               summary.meanSimilarity, summary.errors)
    }

    /// `coding-20261104-093005.json`
    public static func fileName(suite: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(suite)-\(formatter.string(from: date)).json"
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    private static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "⏎")
    }
}
