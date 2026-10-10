import SwiftUI
import TalkToMyMacCore

/// Settings tab showing pipeline latency from the `transcription_metrics` table.
///
/// Latency is normalised by the size of the work so that a mix of short and long
/// dictations doesn't skew the numbers: transcription per second of audio (speech-to-text
/// processes the whole recording, pauses included) and formatting per word sent to the LLM.
/// Plain per-dictation figures are shown alongside for context.
///
/// Transcription and formatting each get one section per model, since models differ widely
/// in speed. Remote models also show the tokens they were billed for, to track cost.
@available(macOS 26.0, *)
struct InstrumentationView: View {
    let store: TranscriptionStore
    let settings: FormattingSettings

    @State private var period: Period = .week
    @State private var rows: [DictationMetrics] = []

    enum Period: String, CaseIterable, Identifiable {
        case day = "24 Hours"
        case week = "7 Days"
        case month = "30 Days"
        case all = "All Time"

        var id: Self { self }

        var since: Date? {
            let day: TimeInterval = 24 * 60 * 60
            switch self {
            case .day:   return Date(timeIntervalSinceNow: -day)
            case .week:  return Date(timeIntervalSinceNow: -7 * day)
            case .month: return Date(timeIntervalSinceNow: -30 * day)
            case .all:   return nil
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if rows.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Dictations",
                        systemImage: "chart.bar",
                        description: Text("Metrics appear here after you dictate.")
                    )
                }
            } else {
                ForEach(transcriptionEngines, id: \.self) { engine in
                    transcriptionSection(for: engine)
                }
                ForEach(formattingModels, id: \.self) { model in
                    formattingSection(for: model)
                    if model.isRemote {
                        tokenSection(for: model)
                    }
                }
                volumeSection
            }
        }
        // Grouped is the standard macOS settings layout (as in System Settings): rounded
        // section boxes, titles above, notes below, labels leading and values trailing.
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onChange(of: period) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: TranscriptionStore.didChangeNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        rows = store.metrics(since: period.since)
    }

    // MARK: Sections

    /// Speech-to-text engines used in this period, in the order they're declared.
    private var transcriptionEngines: [TranscriptionEngine] {
        let used = Set(rows.compactMap(\.transcriptionEngine))
        return TranscriptionEngine.allCases.filter(used.contains)
    }

    private func transcriptionSection(for engine: TranscriptionEngine) -> some View {
        let rows = rows.filter { $0.transcriptionEngine == engine }
        return Section {
            StatsTable(rows: [
                StatsRow(
                    label: "Per second of audio",
                    summary: LatencyStats.perUnit(rows.map { ($0.transcriptionMs, $0.audioSeconds) })
                ),
                StatsRow(
                    label: "Per dictation",
                    summary: LatencyStats.perSample(rows.map(\.transcriptionMs))
                ),
            ])
        } header: {
            Text("Transcription · \(engine.displayName)")
        } footer: {
            SectionNote("Speech-to-text time, weighted by recording length. "
                        + "Based on \(Self.dictations(rows.count)).")
        }
    }

    /// Models formatting was attempted with in this period: on-device first, then by name.
    private var formattingModels: [FormattingModel] {
        Set(rows.compactMap(\.formattingModel)).sorted {
            ($0.isRemote ? 1 : 0, $0.displayName) < ($1.isRemote ? 1 : 0, $1.displayName)
        }
    }

    private func formattingSection(for model: FormattingModel) -> some View {
        let attempts = rows.filter { $0.formattingModel == model }
        // Only runs where the LLM actually produced the output — a failed or timed-out run
        // says nothing about how fast formatting is.
        let applied = attempts.filter { $0.llmApplied && $0.formattingMs != nil }
        let failed = attempts.count - applied.count
        let words = WordTotals.sum(attempts.map { (input: $0.rawWordCount, output: $0.formattedWordCount) })

        return Section {
            StatsTable(rows: [
                StatsRow(
                    label: "Per word",
                    summary: LatencyStats.perUnit(applied.map { ($0.formattingMs!, Double($0.rawWordCount)) })
                ),
                StatsRow(
                    label: "Per dictation",
                    summary: LatencyStats.perSample(applied.compactMap(\.formattingMs))
                ),
            ])
            WordTable(totals: words)
        } header: {
            Text("LLM Formatting · \(model.displayName)")
        } footer: {
            SectionNote((model.isRemote ? "Round-trip time to the provider" : "On-device time")
                        + ", weighted by word count. Based on \(Self.dictations(applied.count))"
                        + (failed > 0 ? "; \(failed) excluded because the model failed or timed out." : ".")
                        + " Words in and out cover all \(Self.dictations(words.dictations)) sent to this model;"
                        + " a failed run's output is the unformatted transcript.")
        }
    }

    private func tokenSection(for model: FormattingModel) -> some View {
        let totals = TokenTotals.sum(rows.filter { $0.formattingModel == model }.map(\.tokenUsage))

        return Section {
            if let totals {
                TokenTable(totals: totals, price: settings.price(for: model))
            } else {
                Text("No token usage reported yet.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Tokens & Cost · \(model.displayName)")
        } footer: {
            SectionNote("As reported by the provider, including failed calls that were still billed. "
                        + "Output includes reasoning tokens; input includes cached tokens. "
                        + "Cost is estimated at the current prices in the Models tab.")
        }
    }

    private var volumeSection: some View {
        let words = rows.reduce(0) { $0 + $1.rawWordCount }
        let changed = rows.filter(\.llmApplied).reduce(0) { $0 + $1.wordsChanged }
        let llmWords = rows.filter(\.llmApplied).reduce(0) { $0 + $1.rawWordCount }
        let audio = rows.reduce(0) { $0 + $1.audioSeconds }

        return Section("Volume") {
            LabeledContent("Dictations", value: rows.count.formatted())
            LabeledContent("Words dictated", value: words.formatted())
            LabeledContent("Audio recorded", value: Self.formatAudio(audio))
            if llmWords > 0 {
                LabeledContent(
                    "Words changed by LLM",
                    value: "\(changed.formatted()) (\((Double(changed) / Double(llmWords)).formatted(.percent.precision(.fractionLength(0)))))"
                )
            }
        }
        .monospacedDigit()
    }

    private static func dictations(_ count: Int) -> String {
        "\(count.formatted()) dictation\(count == 1 ? "" : "s")"
    }

    /// "42s", "13m 38s", "2h 05m".
    private static func formatAudio(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        if m > 0 { return "\(m)m \(String(format: "%02d", s))s" }
        return "\(s)s"
    }
}

// MARK: - Stats table

private struct StatsRow {
    let label: String
    let summary: LatencySummary?
}

/// A small table: row label on the leading edge, then right-aligned Average and P99
/// columns. The numeric columns have fixed widths so they line up across sections.
private struct StatsTable: View {
    let rows: [StatsRow]

    private static let valueColumnWidth: CGFloat = 76

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                    .frame(maxWidth: .infinity)
                Text("Average")
                    .frame(width: Self.valueColumnWidth, alignment: .trailing)
                Text("P99")
                    .frame(width: Self.valueColumnWidth, alignment: .trailing)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            ForEach(rows, id: \.label) { row in
                Divider()
                GridRow {
                    Text(row.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Self.format(row.summary?.mean))
                        .frame(width: Self.valueColumnWidth, alignment: .trailing)
                    Text(Self.format(row.summary?.p99))
                        .frame(width: Self.valueColumnWidth, alignment: .trailing)
                }
                .monospacedDigit()
            }
        }
    }

    private static func format(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        if ms >= 1000 {
            return (ms / 1000).formatted(.number.precision(.fractionLength(2))) + " s"
        }
        return ms.formatted(.number.precision(.fractionLength(ms < 10 ? 1 : 0))) + " ms"
    }
}

// MARK: - Token table

/// Total and per-dictation token counts and estimated cost for one remote model, laid out
/// like `StatsTable`. The cost row is left out when the model has no known price.
private struct TokenTable: View {
    let totals: TokenTotals
    let price: TokenPrice?

    private static let valueColumnWidth: CGFloat = 76

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                    .frame(maxWidth: .infinity)
                Text("Total")
                    .frame(width: Self.valueColumnWidth, alignment: .trailing)
                Text("Average")
                    .frame(width: Self.valueColumnWidth, alignment: .trailing)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            row("Input", total: totals.input)
            row("Cached input", total: totals.cached, indented: true)
            row("Output", total: totals.output)
            row("Reasoning", total: totals.reasoning, indented: true)
            row("Total", total: totals.total)
            if let price {
                Divider()
                GridRow {
                    Text("Estimated cost")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Self.dollars(totals.cost(at: price)))
                        .frame(width: Self.valueColumnWidth, alignment: .trailing)
                    Text(Self.dollars(totals.averageCost(at: price)))
                        .frame(width: Self.valueColumnWidth, alignment: .trailing)
                }
                .fontWeight(.medium)
            }
        }
        .monospacedDigit()
    }

    /// Dictations cost fractions of a cent, so small amounts keep a few significant digits:
    /// "$1.24", "$0.012", "$0.000045".
    private static func dollars(_ amount: Double) -> String {
        let format = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        if amount >= 1 || amount == 0 {
            return amount.formatted(format.precision(.fractionLength(2)))
        }
        return amount.formatted(format.precision(.significantDigits(2)))
    }

    @ViewBuilder
    private func row(_ label: String, total: Int, indented: Bool = false) -> some View {
        Divider()
        GridRow {
            Text(label)
                .foregroundStyle(indented ? .secondary : .primary)
                .padding(.leading, indented ? 12 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(total.formatted())
                .frame(width: Self.valueColumnWidth, alignment: .trailing)
            Text((Double(total) / Double(totals.dictations)).formatted(.number.precision(.fractionLength(0))))
                .frame(width: Self.valueColumnWidth, alignment: .trailing)
        }
    }
}

// MARK: - Word table

/// Total and per-dictation words sent to and returned by one formatting model, laid out
/// like `TokenTable`.
private struct WordTable: View {
    let totals: WordTotals

    private static let valueColumnWidth: CGFloat = 76

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                    .frame(maxWidth: .infinity)
                Text("Total")
                    .frame(width: Self.valueColumnWidth, alignment: .trailing)
                Text("Average")
                    .frame(width: Self.valueColumnWidth, alignment: .trailing)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            row("Words in", total: totals.input)
            row("Words out", total: totals.output)
        }
        .monospacedDigit()
    }

    @ViewBuilder
    private func row(_ label: String, total: Int) -> some View {
        Divider()
        GridRow {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(total.formatted())
                .frame(width: Self.valueColumnWidth, alignment: .trailing)
            Text(totals.dictations == 0 ? "—" : (Double(total) / Double(totals.dictations)).formatted(.number.precision(.fractionLength(0))))
                .frame(width: Self.valueColumnWidth, alignment: .trailing)
        }
    }
}

/// Explanatory text under a section, styled like System Settings' footnotes.
private struct SectionNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
