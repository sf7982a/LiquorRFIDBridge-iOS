//
//  PersistentQueue.swift
//  LiquorRFIDBridge
//
//  A lightweight SQLite-backed queue for crash-safe offline storage of RFID tags.
//

import Foundation
import SQLite3

// SQLite helper: destructor for bind APIs to copy string data
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Crash-safe persistent queue stored in SQLite.
/// Stores individual RFIDTag JSON payloads and scheduling metadata for retries.
final class PersistentQueue {
    
    struct Item {
        let rowId: Int64
        let createdAt: Date
        let attemptCount: Int
        let nextAttemptAt: Date
        let payloadJSON: String
        let organizationId: String
        let sessionId: String?
        let endpoint: String
        let lastError: String?
    }
    
    private let dbPath: String
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "PersistentQueue.sqlite")
    
    init(filename: String = "queue.sqlite") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.dbPath = dir.appendingPathComponent(filename).path
        open()
        createTable()
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    // MARK: - DB Setup
    
    private func open() {
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            print("SQLite open error: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS queue_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            attempt_count INTEGER NOT NULL,
            next_attempt_at REAL NOT NULL,
            payload TEXT NOT NULL,
            organization_id TEXT NOT NULL,
            session_id TEXT,
            endpoint TEXT NOT NULL,
            last_error TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_queue_ready ON queue_items(next_attempt_at, attempt_count);
        """
        queue.sync {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                print("SQLite create table error: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }
    
    // MARK: - Operations
    
    func enqueue(payloadJSON: String,
                 organizationId: String,
                 sessionId: String?,
                 endpoint: String,
                 scheduleAt: Date = Date(),
                 initialAttemptCount: Int = 0) {
        // Enforce DB-level queue bounds with FIFO eviction
        let current = countAll()
        if current >= AppConfig.maxQueueSize {
            evictOldest(count: (current - AppConfig.maxQueueSize) + 1)
        }
        let sql = """
        INSERT INTO queue_items (created_at, attempt_count, next_attempt_at, payload, organization_id, session_id, endpoint)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, scheduleAt.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 2, Int32(initialAttemptCount))
                sqlite3_bind_double(stmt, 3, scheduleAt.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 4, payloadJSON, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, organizationId, -1, SQLITE_TRANSIENT)
                if let s = sessionId {
                    sqlite3_bind_text(stmt, 6, s, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                sqlite3_bind_text(stmt, 7, endpoint, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("SQLite enqueue error: \(String(cString: sqlite3_errmsg(db)))")
                }
            } else {
                print("SQLite prepare enqueue error: \(String(cString: sqlite3_errmsg(db)))")
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func fetchReady(limit: Int, now: Date = Date(), maxAttempts: Int) -> [Item] {
        let sql = """
        SELECT id, created_at, attempt_count, next_attempt_at, payload, organization_id, session_id, endpoint, last_error
        FROM queue_items
        WHERE next_attempt_at <= ? AND attempt_count < ?
        ORDER BY created_at ASC
        LIMIT ?;
        """
        var results: [Item] = []
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 2, Int32(maxAttempts))
                sqlite3_bind_int(stmt, 3, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let rowId = sqlite3_column_int64(stmt, 0)
                    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
                    let attemptCount = Int(sqlite3_column_int(stmt, 2))
                    let nextAttemptAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                    let payload = String(cString: sqlite3_column_text(stmt, 4))
                    let org = String(cString: sqlite3_column_text(stmt, 5))
                    let sess = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 6))
                    let endpoint = String(cString: sqlite3_column_text(stmt, 7))
                    let lastErr = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 8))
                    results.append(Item(rowId: rowId,
                                        createdAt: createdAt,
                                        attemptCount: attemptCount,
                                        nextAttemptAt: nextAttemptAt,
                                        payloadJSON: payload,
                                        organizationId: org,
                                        sessionId: sess,
                                        endpoint: endpoint,
                                        lastError: lastErr))
                }
            } else {
                print("SQLite prepare fetchReady error: \(String(cString: sqlite3_errmsg(db)))")
            }
            sqlite3_finalize(stmt)
        }
        return results
    }
    
    func delete(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = "DELETE FROM queue_items WHERE id IN (\(placeholders));"
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                for (index, id) in ids.enumerated() {
                    sqlite3_bind_int64(stmt, Int32(index + 1), id)
                }
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("SQLite delete error: \(String(cString: sqlite3_errmsg(db)))")
                }
            } else {
                print("SQLite prepare delete error: \(String(cString: sqlite3_errmsg(db)))")
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func markFailed(ids: [Int64], error: String, nextAttemptAt: Date) {
        guard !ids.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = """
        UPDATE queue_items
        SET attempt_count = attempt_count + 1,
            next_attempt_at = ?,
            last_error = ?
        WHERE id IN (\(placeholders));
        """
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, nextAttemptAt.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 2, error, -1, SQLITE_TRANSIENT)
                var bindIndex: Int32 = 3
                for id in ids {
                    sqlite3_bind_int64(stmt, bindIndex, id)
                    bindIndex += 1
                }
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("SQLite update error: \(String(cString: sqlite3_errmsg(db)))")
                }
            } else {
                print("SQLite prepare update error: \(String(cString: sqlite3_errmsg(db)))")
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func countAll() -> Int {
        let sql = "SELECT COUNT(*) FROM queue_items;"
        var count = 0
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(stmt, 0))
                }
            } else {
                print("SQLite prepare count error: \(String(cString: sqlite3_errmsg(db)))")
            }
            sqlite3_finalize(stmt)
        }
        return count
    }
    
    private func evictOldest(count: Int) {
        guard count > 0 else { return }
        let sqlSelect = "SELECT id FROM queue_items ORDER BY created_at ASC LIMIT ?;"
        var idsToDelete: [Int64] = []
        queue.sync {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlSelect, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(count))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = sqlite3_column_int64(stmt, 0)
                    idsToDelete.append(id)
                }
            } else {
                print("SQLite prepare evict select error: \(String(cString: sqlite3_errmsg(db)))")
            }
            sqlite3_finalize(stmt)
        }
        delete(ids: idsToDelete)
    }
}


