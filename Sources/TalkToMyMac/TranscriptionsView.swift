import AppKit
import SwiftUI
import TalkToMyMacCore

/// Settings tab listing past dictations (the delivered, post-LLM text), newest first, a page
/// at a time. Clicking one opens what each pipeline step did to it.
@available(macOS 26.0, *)
struct TranscriptionsView: View {
    let store: TranscriptionStore

    private static let pageSize = 10

    @State private var records: [TranscriptionRecord] = []
    @State private var pagination = Pagination(pageSize: pageSize, totalCount: 0)
    @State private var page = 0
    @State private var path: [TranscriptionRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No Transcriptions",
                        systemImage: "text.bubble",
                        description: Text("Your dictations appear here.")
                    )
                } else {
                    VStack(spacing: 0) {
                        List(Array(records.enumerated()), id: \.element.id) { index, record in
                            NavigationLink(value: TranscriptionRoute(id: record.id)) {
                                TranscriptionRow(record: record)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Self.stripe(for: index))
                        }
                        // Stripes are drawn per row rather than with `alternatesRowBackgrounds`,
                        // which also stripes the empty space below the last row.
                        .listStyle(.inset)

                        Divider()
                        pager
                    }
                }
            }
            .navigationDestination(for: TranscriptionRoute.self) { route in
                TranscriptionDetailView(store: store, id: route.id) { path.removeLast() }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: TranscriptionStore.didChangeNotification)) { _ in
            reload()
        }
    }

    /// The system's alternating row colors, applied to real rows only.
    private static func stripe(for index: Int) -> Color {
        let colors = NSColor.alternatingContentBackgroundColors
        return Color(nsColor: colors[index % colors.count])
    }

    private var pager: some View {
        HStack {
            Button {
                show(page: page - 1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(!pagination.hasPrevious(page))

            Spacer()
            Text(pagination.rangeLabel(of: page))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()

            Button {
                show(page: page + 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(!pagination.hasNext(page))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func show(page newPage: Int) {
        page = newPage
        reload()
    }

    /// Fetches only the current page, keeping it within the pages that exist after a purge.
    private func reload() {
        pagination = Pagination(pageSize: Self.pageSize, totalCount: store.transcriptionCount())
        page = pagination.clamped(page)
        records = store.recentTranscriptions(limit: Self.pageSize, offset: pagination.offset(of: page))
    }
}

/// Navigation value for one dictation's detail screen.
private struct TranscriptionRoute: Hashable {
    let id: String
}

private struct TranscriptionRow: View {
    let record: TranscriptionRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.text)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            CopyButton(text: record.text)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy") { CopyButton.copy(record.text) }
        }
    }
}

// MARK: - Detail

/// One dictation, step by step: what speech-to-text heard, what deterministic cleanup changed,
/// and what the LLM delivered.
@available(macOS 26.0, *)
private struct TranscriptionDetailView: View {
    let store: TranscriptionStore
    let id: String
    /// Returns to the list.
    let onBack: () -> Void

    @State private var detail: TranscriptionDetail?

    var body: some View {
        VStack(spacing: 0) {
            backBar
            Divider()
            if let detail {
                content(detail)
            } else {
                ContentUnavailableView("Transcription Not Found", systemImage: "text.bubble",
                                       description: Text("It may have been purged."))
                    .frame(maxHeight: .infinity)
            }
        }
        // The back bar replaces the toolbar's own back button, which doesn't reliably appear
        // for a stack nested in the Settings split view.
        .navigationBarBackButtonHidden(true)
        .navigationTitle(detail.map { $0.record.timestamp.formatted(date: .abbreviated, time: .shortened) }
                         ?? "Transcription")
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: TranscriptionStore.didChangeNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        detail = store.detail(id: id)
    }

    private var backBar: some View {
        BackBar(title: detail?.record.timestamp.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()),
                help: "Back to Transcriptions", action: onBack)
    }

    private func content(_ detail: TranscriptionDetail) -> some View {
        let stages = detail.stages
        let metrics = detail.metrics
        return Form {
            Section {
                if let text = detail.rawText {
                    StageText(text: text)
                } else {
                    missing("Raw transcriptions were purged.")
                }
                if let metrics {
                    LabeledContent("Model", value: metrics.transcriptionEngine?.displayName ?? "Unknown")
                    LabeledContent("Audio", value: Self.seconds(metrics.audioSeconds))
                    LabeledContent("Took", value: Self.milliseconds(metrics.transcriptionMs))
                }
            } header: {
                Text("1 · Speech-to-Text")
            }

            Section {
                switch stages.cleanup {
                case .notRecorded:
                    missing("Not recorded — this dictation is older than cleanup history, or it was purged.")
                case .off:
                    missing("Didn't run: cleanup was off, or the dictation wasn't in English.")
                case .applied(let changed):
                    if let text = detail.cleanedText { StageText(text: text) }
                    if let changed { LabeledContent("Words changed", value: changed.formatted()) }
                }
            } header: {
                Text("2 · Deterministic Cleanup")
            } footer: {
                Text("Includes any edits made while reviewing the transcript.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                switch stages.formatting {
                case .notRecorded:
                    missing("Metrics were purged, so it's unknown whether the LLM formatted this.")
                    StageText(text: detail.record.text)
                case .skipped:
                    missing("Skipped: formatting was off, or the dictation was too short. "
                            + "The text below is what was delivered.")
                    StageText(text: detail.record.text)
                case .failed:
                    missing("The model failed or timed out, so the unformatted text was delivered.")
                    StageText(text: detail.record.text)
                case .applied(let changed):
                    StageText(text: detail.record.text)
                    if let changed { LabeledContent("Words changed", value: changed.formatted()) }
                }
                if let metrics, let model = metrics.formattingModel {
                    LabeledContent("Model", value: model.displayName)
                    if let ms = metrics.formattingMs {
                        LabeledContent("Took", value: Self.milliseconds(ms))
                    }
                    if let usage = metrics.tokenUsage {
                        LabeledContent("Tokens", value: "\(usage.input.formatted()) in · \(usage.output.formatted()) out")
                    }
                }
            } header: {
                Text("3 · LLM Formatting")
            }
        }
        .formStyle(.grouped)
    }

    private func missing(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    private static func milliseconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " ms"
    }
}

/// A stage's text, selectable, with a copy button.
private struct StageText: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text.isEmpty ? "(empty)" : text)
                .textSelection(.enabled)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            CopyButton(text: text)
        }
    }
}

private struct CopyButton: View {
    let text: String

    @State private var copied = false

    var body: some View {
        Button {
            Self.copy(text)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .frame(width: 16)
        }
        .buttonStyle(.borderless)
        .help("Copy to clipboard")
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
