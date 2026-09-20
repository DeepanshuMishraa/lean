import Foundation
import SQLite3

enum AppDatabaseError: Error, Equatable {
    case open(String)
    case execute(String)
    case prepare(String)
    case bind(String)
    case step(String)
    case decode(String)
}

final class AppDatabase {
    private var handle: OpaquePointer?
    private let lock = NSLock()

    init(url: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if let database { sqlite3_close(database) }
            throw AppDatabaseError.open(message)
        }
        handle = database

        do {
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA synchronous=NORMAL;")
            try execute("PRAGMA busy_timeout=5000;")
            try execute("CREATE TABLE IF NOT EXISTS app_state (key TEXT PRIMARY KEY, value BLOB NOT NULL) WITHOUT ROWID;")
        } catch {
            sqlite3_close(database)
            handle = nil
            throw error
        }
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    static func openDefault() -> AppDatabase? {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Lean", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try AppDatabase(url: directory.appendingPathComponent("Lean.sqlite3"))
        } catch {
            NSLog("Could not open Lean database: %@", String(describing: error))
            return nil
        }
    }

    func value<T: Decodable>(_ type: T.Type, forKey key: String) -> Result<T?, AppDatabaseError> {
        locked {
            guard let handle else { return .failure(.open("Database is closed")) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT value FROM app_state WHERE key = ?1", -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                return .failure(.prepare(errorMessage(handle)))
            }
            defer { sqlite3_finalize(statement) }

            return key.withCString { keyBytes in
                guard sqlite3_bind_text(statement, 1, keyBytes, -1, nil) == SQLITE_OK else {
                    return .failure(.bind(errorMessage(handle)))
                }

                let stepResult = sqlite3_step(statement)
                if stepResult == SQLITE_DONE { return .success(nil) }
                guard stepResult == SQLITE_ROW else { return .failure(.step(errorMessage(handle))) }

                let count = Int(sqlite3_column_bytes(statement, 0))
                guard let bytes = sqlite3_column_blob(statement, 0) else {
                    return .failure(.decode("Stored value for \(key) is empty"))
                }
                let data = Data(bytes: bytes, count: count)
                do {
                    return .success(try JSONDecoder().decode(type, from: data))
                } catch {
                    return .failure(.decode("Could not decode \(key): \(error.localizedDescription)"))
                }
            }
        }
    }

    @discardableResult
    func set<T: Encodable>(_ value: T, forKey key: String) -> Result<Void, AppDatabaseError> {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            return .failure(.decode("Could not encode \(key): \(error.localizedDescription)"))
        }

        return locked {
            guard let handle else { return .failure(.open("Database is closed")) }
            var statement: OpaquePointer?
            let sql = "INSERT INTO app_state (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                return .failure(.prepare(errorMessage(handle)))
            }
            defer { sqlite3_finalize(statement) }

            return key.withCString { keyBytes in
                data.withUnsafeBytes { valueBytes in
                    guard sqlite3_bind_text(statement, 1, keyBytes, -1, nil) == SQLITE_OK else {
                        return .failure(.bind(errorMessage(handle)))
                    }
                    guard sqlite3_bind_blob(statement, 2, valueBytes.baseAddress, Int32(valueBytes.count), nil) == SQLITE_OK else {
                        return .failure(.bind(errorMessage(handle)))
                    }
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        return .failure(.step(errorMessage(handle)))
                    }
                    return .success(())
                }
            }
        }
    }

    private func execute(_ sql: String) throws {
        guard let handle else { throw AppDatabaseError.open("Database is closed") }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw AppDatabaseError.execute(errorMessage(handle))
        }
    }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    private func errorMessage(_ handle: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(handle))
    }
}
