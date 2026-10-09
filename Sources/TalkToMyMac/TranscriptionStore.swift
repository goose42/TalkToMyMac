import Foundation
import SQLite3
import TalkToMyMacCore

/// A single transcription record, as shown in the Transcriptions menu.
struct TranscriptionRecord {
    let id: String       // UUID string
    let timestamp: Date
    let text: String
}

/// One row of `transcription_metrics`.
struct DictationMetrics {
    let timestamp: Date
    let audioSeconds: Double
    let transcriptionMs: Double
    let formattingMs: Double?
    let llmApplied: Bool
    let rawWordCount: Int
    let formattedWordCount: Int
    let wordsChanged: Int
    /// The model formatting was attempted with; nil if it wasn't attempted.
    let formattingModel: FormattingModel?
    /// Tokens a remote model reported; nil for on-device models and unmetered failures.
    let tokenUsage: TokenUsage?
}

/// Persists transcription history and pipeline metrics in a SQLite database.
///
/// Each dictation writes one row to each of three independent tables, all sharing the same
/// `id` and `timestamp`:
/// - `raw_transcriptions` — exactly what the speech-to-text model produced.
/// - `formatted_transcriptions` — what was delivered after the LLM step (the raw text
///   unchanged if the LLM was off or failed).
/// - `transcription_metrics` — timings, word counts, the formatting model, and (for remote
///   models) token usage for the run.
final class TranscriptionStore {
    /// Posted on the main queue after a dictation is recorded.
    static let didChangeNotification = Notification.Name("TranscriptionStoreDidChange")

    /// The tables the store manages. Raw values are the SQL table names.
    enum Table: String, CaseIterable {
        case raw = "raw_transcriptions"
        case formatted = "formatted_transcriptions"
        case metrics = "transcription_metrics"
    }

    /// Row count and on-disk footprint of one table.
    struct TableUsage {
        let table: Table
        let rowCount: Int
        /// Bytes of pages held by the table and its indexes; nil if SQLite can't report it.
        let bytes: Int64?
    }

    static var databaseURL: URL {
        AudioCapture.dataDirectory.appendingPathComponent("transcription_history.sqlite")
    }

    private var db: OpaquePointer?

    /// Opens (or creates) the database at the standard location.
    init() {
        let dir = AudioCapture.dataDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = Self.databaseURL.path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[TranscriptionStore] Failed to open database at \(dbPath)")
            db = nil
            return
        }

        let createSQL = """
            CREATE TABLE IF NOT EXISTS raw_transcriptions (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                text TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS formatted_transcriptions (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                text TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS transcription_metrics (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                audio_seconds REAL NOT NULL,
                transcription_ms REAL NOT NULL,
                formatting_ms REAL,               -- NULL when no formatter is configured
                llm_applied INTEGER NOT NULL,     -- 0 if the LLM was off, failed, or timed out
                raw_word_count INTEGER NOT NULL,
                formatted_word_count INTEGER NOT NULL,
                words_changed INTEGER NOT NULL,   -- word-level edit distance, raw → formatted
                formatting_provider TEXT,         -- NULL when formatting wasn't attempted
                formatting_model TEXT,
                input_tokens INTEGER,             -- NULL unless a remote model reported usage
                output_tokens INTEGER,            -- includes reasoning_tokens
                reasoning_tokens INTEGER,
                cached_tokens INTEGER             -- part of input_tokens
            );
            """
        if sqlite3_exec(db, createSQL, nil, nil, nil) != SQLITE_OK {
            print("[TranscriptionStore] Failed to create tables: \(errorMessage)")
        }

        migrateLegacyTable()
        addFormattingModelColumns()
    }

    deinit {
        sqlite3_close(db)
    }

    /// Earlier versions kept a single `transcriptions` table holding only the final
    /// (post-LLM) text. Move those rows into `formatted_transcriptions` — their raw text and
    /// metrics were never recorded — then drop the old table. Runs once; a no-op afterwards.
    private func migrateLegacyTable() {
        let sql = """
            BEGIN;
            INSERT OR IGNORE INTO formatted_transcriptions (id, timestamp, text)
                SELECT id, timestamp, text FROM transcriptions;
            DROP TABLE transcriptions;
            COMMIT;
            """
        guard tableExists("transcriptions") else { return }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("[TranscriptionStore] Legacy migration failed: \(errorMessage)")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
        } else {
            print("[TranscriptionStore] Migrated legacy transcriptions table")
        }
    }

    /// Metrics tables created before formatting could run on a remote model lack the model
    /// and token columns. Add them, and attribute earlier formatting attempts to the
    /// on-device model — the only one there was. Runs once; a no-op afterwards.
    private func addFormattingModelColumns() {
        guard !columnExists("formatting_provider", in: Table.metrics.rawValue) else { return }
        let sql = """
            BEGIN;
            ALTER TABLE transcription_metrics ADD COLUMN formatting_provider TEXT;
            ALTER TABLE transcription_metrics ADD COLUMN formatting_model TEXT;
            ALTER TABLE transcription_metrics ADD COLUMN input_tokens INTEGER;
            ALTER TABLE transcription_metrics ADD COLUMN output_tokens INTEGER;
            ALTER TABLE transcription_metrics ADD COLUMN reasoning_tokens INTEGER;
            ALTER TABLE transcription_metrics ADD COLUMN cached_tokens INTEGER;
            UPDATE transcription_metrics
                SET formatting_provider = '\(FormattingModel.appleOnDevice.provider.rawValue)',
                    formatting_model = '\(FormattingModel.appleOnDevice.modelID)'
                WHERE formatting_ms IS NOT NULL;
            COMMIT;
            """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("[TranscriptionStore] Adding formatting model columns failed: \(errorMessage)")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
        } else {
            print("[TranscriptionStore] Added formatting model columns")
        }
    }

    // MARK: - Write

    /// Records one dictation across all three tables, atomically. Returns the formatted
    /// record (what the menu shows) on success.
    @discardableResult
    func insert(_ result: PipelineResult, audioSeconds: Double) -> TranscriptionRecord? {
        guard db != nil else { return nil }

        let id = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970

        guard sqlite3_exec(db, "BEGIN;", nil, nil, nil) == SQLITE_OK else {
            print("[TranscriptionStore] Begin failed: \(errorMessage)")
            return nil
        }

        let ok =
            execute(
                "INSERT INTO raw_transcriptions (id, timestamp, text) VALUES (?, ?, ?);",
                [.text(id), .real(timestamp), .text(result.rawText)]
            )
            && execute(
                "INSERT INTO formatted_transcriptions (id, timestamp, text) VALUES (?, ?, ?);",
                [.text(id), .real(timestamp), .text(result.finalText)]
            )
            && execute(
                """
                INSERT INTO transcription_metrics (
                    id, timestamp, audio_seconds, transcription_ms, formatting_ms, llm_applied,
                    raw_word_count, formatted_word_count, words_changed,
                    formatting_provider, formatting_model,
                    input_tokens, output_tokens, reasoning_tokens, cached_tokens
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                [
                    .text(id),
                    .real(timestamp),
                    .real(audioSeconds),
                    .real(Self.milliseconds(result.transcriptionDuration)),
                    result.formattingDuration.map { .real(Self.milliseconds($0)) } ?? .null,
                    .int(result.llmApplied ? 1 : 0),
                    .int(WordDiff.wordCount(result.rawText)),
                    .int(WordDiff.wordCount(result.finalText)),
                    .int(WordDiff.changedWords(from: result.rawText, to: result.finalText)),
                    result.formattingModel.map { .text($0.provider.rawValue) } ?? .null,
                    result.formattingModel.map { .text($0.modelID) } ?? .null,
                    result.tokenUsage.map { .int($0.input) } ?? .null,
                    result.tokenUsage.map { .int($0.output) } ?? .null,
                    result.tokenUsage.map { .int($0.reasoning) } ?? .null,
                    result.tokenUsage.map { .int($0.cached) } ?? .null,
                ]
            )

        guard ok, sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            print("[TranscriptionStore] Insert failed, rolling back: \(errorMessage)")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return nil
        }

        print("[TranscriptionStore] Saved transcription \(id)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
        return TranscriptionRecord(
            id: id,
            timestamp: Date(timeIntervalSince1970: timestamp),
            text: result.finalText
        )
    }

    // MARK: - Read

    /// Returns the most recent `limit` delivered (formatted) transcriptions, newest first.
    func recentTranscriptions(limit: Int = 10) -> [TranscriptionRecord] {
        guard let db = db else { return [] }

        let sql = "SELECT id, timestamp, text FROM formatted_transcriptions ORDER BY timestamp DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[TranscriptionStore] Prepare select failed: \(errorMessage)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [TranscriptionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let text = String(cString: sqlite3_column_text(stmt, 2))
            results.append(TranscriptionRecord(id: id, timestamp: timestamp, text: text))
        }
        return results
    }

    /// Metrics rows recorded at or after `since` (all of them if nil), oldest first.
    func metrics(since: Date? = nil) -> [DictationMetrics] {
        guard let db = db else { return [] }

        let sql = """
            SELECT timestamp, audio_seconds, transcription_ms, formatting_ms, llm_applied,
                   raw_word_count, formatted_word_count, words_changed,
                   formatting_provider, formatting_model,
                   input_tokens, output_tokens, reasoning_tokens, cached_tokens
            FROM transcription_metrics WHERE timestamp >= ? ORDER BY timestamp;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[TranscriptionStore] Prepare metrics select failed: \(errorMessage)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, since?.timeIntervalSince1970 ?? 0)

        var results: [DictationMetrics] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(DictationMetrics(
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                audioSeconds: sqlite3_column_double(stmt, 1),
                transcriptionMs: sqlite3_column_double(stmt, 2),
                formattingMs: sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 3),
                llmApplied: sqlite3_column_int(stmt, 4) != 0,
                rawWordCount: Int(sqlite3_column_int64(stmt, 5)),
                formattedWordCount: Int(sqlite3_column_int64(stmt, 6)),
                wordsChanged: Int(sqlite3_column_int64(stmt, 7)),
                formattingModel: Self.formattingModel(stmt, provider: 8, model: 9),
                tokenUsage: Self.tokenUsage(stmt, firstColumn: 10)
            ))
        }
        return results
    }

    /// The model in a row's provider/model columns; nil if formatting wasn't attempted or
    /// the provider is one this version doesn't know.
    private static func formattingModel(_ stmt: OpaquePointer?, provider: Int32, model: Int32) -> FormattingModel? {
        guard let providerText = text(stmt, provider), let modelText = text(stmt, model),
              let provider = FormattingProvider(rawValue: providerText) else { return nil }
        return FormattingModel(provider: provider, modelID: modelText)
    }

    /// Usage from the four token columns starting at `firstColumn`; nil if none was recorded.
    private static func tokenUsage(_ stmt: OpaquePointer?, firstColumn: Int32) -> TokenUsage? {
        guard sqlite3_column_type(stmt, firstColumn) != SQLITE_NULL else { return nil }
        let int = { (offset: Int32) in Int(sqlite3_column_int64(stmt, firstColumn + offset)) }
        return TokenUsage(input: int(0), output: int(1), reasoning: int(2), cached: int(3))
    }

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cString)
    }

    // MARK: - Storage

    /// Size of the database file on disk, including any rollback journal.
    func fileSize() -> Int64 {
        let path = Self.databaseURL.path
        return [path, path + "-journal", path + "-wal"].reduce(0) { total, path in
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber
            return total + (size?.int64Value ?? 0)
        }
    }

    /// Row counts and page usage for each table.
    func tableUsage() -> [TableUsage] {
        guard db != nil else { return [] }
        let bytes = pageBytesByTable()
        return Table.allCases.map { table in
            TableUsage(
                table: table,
                rowCount: Int(scalar("SELECT COUNT(*) FROM \(table.rawValue);") ?? 0),
                bytes: bytes?[table.rawValue]
            )
        }
    }

    /// Deletes every row from `tables`, then vacuums so the file actually shrinks.
    /// Returns false (and logs) on failure, leaving the tables untouched.
    @discardableResult
    func purge(_ tables: [Table]) -> Bool {
        guard db != nil, !tables.isEmpty else { return false }

        let deletes = tables.map { "DELETE FROM \($0.rawValue);" }.joined(separator: "\n")
        guard sqlite3_exec(db, "BEGIN;\n\(deletes)\nCOMMIT;", nil, nil, nil) == SQLITE_OK else {
            print("[TranscriptionStore] Purge failed, rolling back: \(errorMessage)")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return false
        }
        if sqlite3_exec(db, "VACUUM;", nil, nil, nil) != SQLITE_OK {
            print("[TranscriptionStore] Vacuum failed: \(errorMessage)")
        }

        print("[TranscriptionStore] Purged \(tables.map(\.rawValue).joined(separator: ", "))")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
        return true
    }

    /// Bytes of pages per table, with each table's indexes counted toward it. Uses the
    /// `dbstat` virtual table, which is an optional SQLite build feature — nil if missing.
    private func pageBytesByTable() -> [String: Int64]? {
        let sql = """
            SELECT m.tbl_name, SUM(d.pgsize) FROM dbstat d
            JOIN sqlite_master m ON m.name = d.name GROUP BY m.tbl_name;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[TranscriptionStore] dbstat unavailable: \(errorMessage)")
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        var result: [String: Int64] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            result[String(cString: sqlite3_column_text(stmt, 0))] = sqlite3_column_int64(stmt, 1)
        }
        return result
    }

    /// First column of the first row of a parameterless query.
    private func scalar(_ sql: String) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
    }

    // MARK: - Helpers

    private enum Value {
        case text(String)
        case real(Double)
        case int(Int)
        case null
    }

    /// Prepares, binds, and steps a single statement. Returns false (and logs) on failure.
    private func execute(_ sql: String, _ values: [Value]) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[TranscriptionStore] Prepare failed: \(errorMessage)")
            return false
        }
        defer { sqlite3_finalize(stmt) }

        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let s): sqlite3_bind_text(stmt, index, (s as NSString).utf8String, -1, Self.transient)
            case .real(let d): sqlite3_bind_double(stmt, index, d)
            case .int(let i):  sqlite3_bind_int64(stmt, index, Int64(i))
            case .null:        sqlite3_bind_null(stmt, index)
            }
        }
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    private func tableExists(_ name: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?;", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, Self.transient)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func columnExists(_ column: String, in table: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM pragma_table_info(?) WHERE name = ?;", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (table as NSString).utf8String, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, (column as NSString).utf8String, -1, Self.transient)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// Tells SQLite to copy bound strings, since the bridged `NSString` buffers are
    /// temporaries that don't outlive the bind call.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func milliseconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }

    private var errorMessage: String {
        if let msg = sqlite3_errmsg(db) {
            return String(cString: msg)
        }
        return "unknown error"
    }
}
