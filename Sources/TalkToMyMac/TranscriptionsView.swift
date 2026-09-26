import AppKit
import SwiftUI

/// Settings tab listing past dictations (the delivered, post-LLM text), newest first.
@available(macOS 26.0, *)
struct TranscriptionsView: View {
    let store: TranscriptionStore

    /// Enough history to be useful without loading an unbounded table into a list.
    private static let limit = 500

    @State private var records: [TranscriptionRecord] = []

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "No Transcriptions",
                    systemImage: "text.bubble",
                    description: Text("Your dictations appear here.")
                )
            } else {
                List(records, id: \.id) { record in
                    TranscriptionRow(record: record)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: TranscriptionStore.didChangeNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        records = store.recentTranscriptions(limit: Self.limit)
    }
}

private struct TranscriptionRow: View {
    let record: TranscriptionRecord

    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Self.copy(record.text)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy") { Self.copy(record.text) }
        }
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
