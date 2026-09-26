import SwiftUI
import TalkToMyMacCore

/// Settings tab showing pipeline latency from the `transcription_metrics` table.
///
/// Latency is normalised by the size of the work so that a mix of short and long
/// dictations doesn't skew the numbers: transcription per second of audio (speech-to-text
/// processes the whole recording, pauses included) and formatting per word sent to the LLM.
/// Plain per-dictation figures are shown alongside for context.
@available(macOS 26.0, *)
struct InstrumentationView: View {
    let store: TranscriptionStore

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
                transcriptionSection
                formattingSection
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

    private var transcriptionSection: some View {
        Section {
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
            Text("Transcription")
        } footer: {
            SectionNote("Speech-to-text time, weighted by recording length. "
                        + "Based on \(Self.dictations(rows.count)).")
        }
    }

    private var formattingSection: some View {
        // Only runs where the LLM actually produced the output — a disabled, failed, or
        // timed-out run says nothing about how fast formatting is.
        let applied = rows.filter { $0.llmApplied && $0.formattingMs != nil }
        let excluded = rows.count - applied.count

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
        } header: {
            Text("LLM Formatting")
        } footer: {
            SectionNote("Apple Intelligence time, weighted by word count. "
                        + "Based on \(Self.dictations(applied.count))"
                        + (excluded > 0 ? "; \(excluded) skipped because the LLM was off, failed, or timed out." : "."))
        }
    }

    private var volumeSection: some View {
        let words = rows.reduce(0) { $0 + $1.rawWordCount }
        let changed = rows.filter(\.llmApplied).reduce(0) { $0 + $1.wordsChanged }
        let llmWords = rows.filter(\.llmApplied).reduce(0) { $0 + $1.rawWordCount }
        let audio = rows.reduce(0) { $0 + $1.audioSeconds }

        return Section("Volume") {
            LabeledContent("Dictations", value: rows.count.formatted())
            LabeledContent("Words transcribed", value: words.formatted())
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
