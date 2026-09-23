import Foundation
import SQLite3
import Security

struct ImportedBookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    let title: String
    let url: URL
}

struct ImportedCredential: Identifiable {
    let host: String
    let username: String
    let password: String
    var id: String { "\(host)\u{1}\(username)" }
}

struct PasswordCSVPreview {
    let credentials: [ImportedCredential]
    let skippedRows: Int
}

struct BrowserImportPreview {
    let bookmarks: [ImportedBookmark]
    let history: [HistoryItem]
}

enum BrowserDataImporter {
    enum ImportError: LocalizedError, Equatable {
        case invalidProfile
        case invalidBookmarks
        case unreadableHistory
        case invalidPasswordCSV
        case invalidHistoryCSV

        var errorDescription: String? {
            switch self {
            case .invalidProfile: "Choose a browser profile folder containing a Bookmarks or History file."
            case .invalidBookmarks: "This JSON file does not contain a supported bookmarks export."
            case .unreadableHistory: "The browser history database could not be read. Close the browser and try again."
            case .invalidPasswordCSV: "The password CSV needs URL, username, and password columns."
            case .invalidHistoryCSV: "The history CSV needs a URL column and can include title and timestamp columns."
            }
        }
    }

    static func readBookmarkExport(_ data: Data) throws -> [ImportedBookmark] {
        let bookmarks = decodeBookmarks(data)
        guard !bookmarks.isEmpty else { throw ImportError.invalidBookmarks }
        return bookmarks
    }

    static func readHistoryCSV(_ data: Data) throws -> [HistoryItem] {
        guard let text = String(data: data, encoding: .utf8) else { throw ImportError.invalidHistoryCSV }
        var rows = parseCSV(text)
        guard let headings = rows.first else { throw ImportError.invalidHistoryCSV }
        rows.removeFirst()
        let header = headings.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
                .lowercased()
        }
        guard let urlIndex = header.firstIndex(where: { ["url", "website"].contains($0) }) else {
            throw ImportError.invalidHistoryCSV
        }
        let titleIndex = header.firstIndex(of: "title")
        let dateIndex = header.firstIndex(where: { ["timestamp", "last_visit_time", "last visited"].contains($0) })
        return rows.compactMap { row in
            guard row.indices.contains(urlIndex),
                  let url = URL(string: row[urlIndex]),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            let title = titleIndex.flatMap { row.indices.contains($0) ? row[$0] : nil }
                .flatMap { $0.isEmpty ? nil : $0 } ?? url.host ?? url.absoluteString
            let date = dateIndex.flatMap { row.indices.contains($0) ? parseDate(row[$0]) : nil } ?? .distantPast
            return HistoryItem(url: url, title: title, timestamp: date)
        }
    }

    static func readProfile(at directory: URL) throws -> BrowserImportPreview {
        let bookmarksURL = directory.appendingPathComponent("Bookmarks")
        let historyURL = directory.appendingPathComponent("History")
        let bookmarks = (try? Data(contentsOf: bookmarksURL)).map(decodeBookmarks) ?? []
        let history: [HistoryItem]
        if FileManager.default.fileExists(atPath: historyURL.path) {
            history = try readHistory(at: historyURL)
        } else {
            history = []
        }
        guard !bookmarks.isEmpty || !history.isEmpty else { throw ImportError.invalidProfile }
        return BrowserImportPreview(bookmarks: bookmarks, history: history)
    }

    static func readPasswordCSV(_ data: Data) throws -> PasswordCSVPreview {
        guard let text = String(data: data, encoding: .utf8) else { throw ImportError.invalidPasswordCSV }
        var rows = parseCSV(text)
        guard let headerRow = rows.first else { throw ImportError.invalidPasswordCSV }
        rows.removeFirst()
        let header = headerRow.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
                .lowercased()
        }
        guard let urlColumn = header.firstIndex(where: { ["url", "login_uri", "website", "site"].contains($0) }),
              let userColumn = header.firstIndex(where: { ["username", "login_username", "user", "email"].contains($0) }),
              let passwordColumn = header.firstIndex(where: { ["password", "login_password"].contains($0) })
        else { throw ImportError.invalidPasswordCSV }

        var credentials: [ImportedCredential] = []
        var seen = Set<String>()
        for row in rows {
            guard row.indices.contains(max(urlColumn, max(userColumn, passwordColumn))),
                  let url = URL(string: row[urlColumn]),
                  let host = url.host?.lowercased(),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  !row[passwordColumn].isEmpty else { continue }
            let username = row[userColumn]
            guard seen.insert("\(host)\u{1}\(username)").inserted else { continue }
            credentials.append(ImportedCredential(host: host, username: username, password: row[passwordColumn]))
        }
        return PasswordCSVPreview(credentials: credentials, skippedRows: rows.count - credentials.count)
    }

    @discardableResult
    static func saveCredentials(_ credentials: [ImportedCredential]) -> (saved: Int, skipped: Int) {
        var saved = 0
        for credential in credentials {
            guard let data = credential.password.data(using: .utf8) else { continue }
            let identity: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: credential.host,
                kSecAttrAccount as String: credential.username,
                kSecAttrLabel as String: "Lean",
            ]
            let fields: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrLabel as String: "Lean",
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            ]
            let status = SecItemUpdate(identity as CFDictionary, fields as CFDictionary)
            let result = status == errSecItemNotFound
                ? SecItemAdd(identity.merging(fields) { _, new in new } as CFDictionary, nil)
                : status
            if result == errSecSuccess { saved += 1 }
        }
        return (saved, credentials.count - saved)
    }

    private static func decodeBookmarks(_ data: Data) -> [ImportedBookmark] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { return [] }
        let groups = ["bookmark_bar", "other", "synced"].compactMap { key -> [[String: Any]]? in
            guard let root = roots[key] as? [String: Any] else { return nil }
            return root["children"] as? [[String: Any]] ?? []
        }
        return groups.flatMap(bookmarks(from:))
    }

    private static func bookmarks(from nodes: [[String: Any]]) -> [ImportedBookmark] {
        nodes.flatMap { node -> [ImportedBookmark] in
            if node["type"] as? String == "folder" {
                return bookmarks(from: node["children"] as? [[String: Any]] ?? [])
            }
            guard node["type"] as? String == "url",
                  let rawURL = node["url"] as? String,
                  let url = URL(string: rawURL),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            else { return [] }
            return [ImportedBookmark(title: node["name"] as? String ?? url.host ?? rawURL, url: url)]
        }
    }

    private static func readHistory(at url: URL) throws -> [HistoryItem] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw ImportError.unreadableHistory
        }
        defer { sqlite3_close(database) }
        let sql = "SELECT url, title, last_visit_time FROM urls WHERE hidden = 0 AND visit_count > 0 ORDER BY last_visit_time DESC LIMIT 3000"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw ImportError.unreadableHistory }
        defer { sqlite3_finalize(statement) }
        var items: [HistoryItem] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW else { throw ImportError.unreadableHistory }
            guard let raw = sqlite3_column_text(statement, 0),
                  let url = URL(string: String(cString: raw)),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let stamp = sqlite3_column_int64(statement, 2)
            let date = stamp > 0
                ? Date(timeIntervalSince1970: Double(stamp) / 1_000_000 - 11_644_473_600)
                : Date.distantPast
            items.append(HistoryItem(url: url, title: title.isEmpty ? url.host ?? url.absoluteString : title, timestamp: date))
        }
        return items
    }

    private static func parseDate(_ text: String) -> Date? {
        if let seconds = Double(text) {
            return seconds > 10_000_000_000
                ? Date(timeIntervalSince1970: seconds / 1_000_000 - 11_644_473_600)
                : Date(timeIntervalSince1970: seconds)
        }
        return ISO8601DateFormatter().date(from: text)
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if quoted {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r" {
                if character == "\r", text.index(after: index) < text.endIndex, text[text.index(after: index)] == "\n" {
                    index = text.index(after: index)
                }
                row.append(field)
                field = ""
                if !row.allSatisfy(\.isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }
        row.append(field)
        if !row.allSatisfy(\.isEmpty) { rows.append(row) }
        return rows
    }
}
