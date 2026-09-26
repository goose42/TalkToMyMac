import Foundation
import SQLite3

/// A single transcription record.
struct TranscriptionRecord {
    let id: String       // UUID string
    let timestamp: Date
    let text: String
}

/// Persists transcription history in a SQLite database.
final class TranscriptionStore {
    private var db: OpaquePointer?

    /// Opens (or creates) the database at the standard location.
    init() {
        let dir = AudioCapture.dataDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("transcription_history.sqlite").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[TranscriptionStore] Failed to open database at \(dbPath)")
            db = nil
            return
        }

        // Create table if it doesn't exist.
        let createSQL = """
            CREATE TABLE IF NOT EXISTS transcriptions (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                text TEXT NOT NULL
            );
            """
        if sqlite3_exec(db, createSQL, nil, nil, nil) != SQLITE_OK {
            print("[TranscriptionStore] Failed to create table: \(errorMessage)")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Write

    /// Insert a new transcription. Returns the record on success.
    @discardableResult
    func insert(text: String) -> TranscriptionRecord? {
        guard let db = db else { return nil }

        let record = TranscriptionRecord(
            id: UUID().uuidString,
            timestamp: Date(),
            text: text
        )

        let sql = "INSERT INTO transcriptions (id, timestamp, text) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[TranscriptionStore] Prepare insert failed: \(errorMessage)")
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (record.id as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, record.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, (record.text as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[TranscriptionStore] Insert failed: \(errorMessage)")
            return nil
        }

        print("[TranscriptionStore] Saved transcription \(record.id)")
        return record
    }

    // MARK: - Read

    /// Returns the most recent `limit` transcriptions, newest first.
    func recentTranscriptions(limit: Int = 10) -> [TranscriptionRecord] {
        guard let db = db else { return [] }

        let sql = "SELECT id, timestamp, text FROM transcriptions ORDER BY timestamp DESC LIMIT ?;"
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

    // MARK: - Helpers

    private var errorMessage: String {
        if let msg = sqlite3_errmsg(db) {
            return String(cString: msg)
        }
        return "unknown error"
    }
}
