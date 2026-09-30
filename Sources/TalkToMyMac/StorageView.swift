import AppKit
import SwiftUI

/// Settings tab showing how much data TalkToMyMac keeps on disk — the transcription
/// database (per table) and the saved audio recordings — with buttons to purge each.
@available(macOS 26.0, *)
struct StorageView: View {
    let store: TranscriptionStore

    @State private var tables: [TranscriptionStore.TableUsage] = []
    @State private var databaseBytes: Int64 = 0
    @State private var recordingCount = 0
    @State private var recordingBytes: Int64 = 0
    @State private var pendingPurge: Purge?

    /// A destructive action awaiting confirmation.
    private enum Purge: Identifiable {
        case tables([TranscriptionStore.Table])
        case recordings

        var id: String {
            switch self {
            case .tables(let tables): return tables.map(\.rawValue).joined(separator: ",")
            case .recordings:         return "recordings"
            }
        }
    }

    var body: some View {
        Form {
            databaseSection
            recordingsSection
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: TranscriptionStore.didChangeNotification)) { _ in
            reload()
        }
        .confirmationDialog(
            pendingPurge.map(confirmationTitle) ?? "",
            isPresented: Binding(get: { pendingPurge != nil }, set: { if !$0 { pendingPurge = nil } }),
            presenting: pendingPurge
        ) { purge in
            Button("Purge", role: .destructive) { perform(purge) }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private func reload() {
        tables = store.tableUsage()
        databaseBytes = store.fileSize()
        (recordingCount, recordingBytes) = AudioCapture.recordingsUsage()
    }

    private func perform(_ purge: Purge) {
        switch purge {
        case .tables(let tables):
            store.purge(tables)
        case .recordings:
            AudioCapture.purgeRecordings()
        }
        reload()
    }

    // MARK: Sections

    private var databaseSection: some View {
        Section {
            ForEach(tables, id: \.table) { usage in
                LabeledContent {
                    HStack(spacing: 12) {
                        Text(usageSummary(rows: usage.rowCount, bytes: usage.bytes))
                            .monospacedDigit()
                        Button("Purge") { pendingPurge = .tables([usage.table]) }
                            .disabled(usage.rowCount == 0)
                    }
                } label: {
                    Text(title(of: usage.table))
                    Text(usage.table.rawValue)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            LabeledContent("File size") {
                HStack(spacing: 12) {
                    Text(Self.bytes(databaseBytes))
                        .monospacedDigit()
                    Button("Purge All") { pendingPurge = .tables(TranscriptionStore.Table.allCases) }
                        .disabled(tables.allSatisfy { $0.rowCount == 0 })
                }
            }
        } header: {
            Text("Transcription Database")
        } footer: {
            Text("Each dictation adds one row to every table. Table sizes include their indexes; "
                 + "the file also holds SQLite's own bookkeeping.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingsSection: some View {
        Section {
            LabeledContent("Audio files") {
                HStack(spacing: 12) {
                    Text(usageSummary(files: recordingCount, bytes: recordingBytes))
                        .monospacedDigit()
                    Button("Purge") { pendingPurge = .recordings }
                        .disabled(recordingCount == 0)
                }
            }
            LabeledContent("Location") {
                Button("Show in Finder") {
                    let dir = AudioCapture.recordingsDirectory
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
            }
        } header: {
            Text("Audio Recordings")
        } footer: {
            Text("Every dictation is saved as a WAV file. Transcription doesn't need them "
                 + "afterwards, so purging them is safe.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Formatting

    private func title(of table: TranscriptionStore.Table) -> String {
        switch table {
        case .raw:       return "Raw transcriptions"
        case .formatted: return "Formatted transcriptions"
        case .metrics:   return "Metrics"
        }
    }

    private func confirmationTitle(_ purge: Purge) -> String {
        switch purge {
        case .tables(let tables) where tables.count == TranscriptionStore.Table.allCases.count:
            return "Purge all transcription history and metrics?"
        case .tables(let tables):
            return "Purge all \(tables.map { title(of: $0).lowercased() }.joined(separator: ", "))?"
        case .recordings:
            return "Delete \(recordingCount) audio recording\(recordingCount == 1 ? "" : "s") (\(Self.bytes(recordingBytes)))?"
        }
    }

    private func usageSummary(rows: Int, bytes: Int64?) -> String {
        let count = "\(rows.formatted()) row\(rows == 1 ? "" : "s")"
        return bytes.map { "\(count) · \(Self.bytes($0))" } ?? count
    }

    private func usageSummary(files: Int, bytes: Int64) -> String {
        "\(files.formatted()) file\(files == 1 ? "" : "s") · \(Self.bytes(bytes))"
    }

    private static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }
}
