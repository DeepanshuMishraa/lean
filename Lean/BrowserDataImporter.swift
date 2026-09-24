import Foundation
import SQLite3

struct ImportedBookmark: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let title: String
    let url: URL
}

struct ImportedCredential: Identifiable {
    let origin: URL
    let username: String
    let password: String
    var host: String { origin.host?.lowercased() ?? origin.absoluteString }
    var id: String {
        let scheme = origin.scheme?.lowercased() ?? ""
        let port = (scheme == "https" && origin.port == 443) || (scheme == "http" && origin.port == 80) ? nil : origin.port
        return "\(scheme)://\(host)\(port.map { ":\($0)" } ?? "")\u{1}\(username)"
    }
}

struct PasswordCSVPreview {
    let credentials: [ImportedCredential]
    let skippedRows: Int
}

struct BrowserImportPreview: Sendable {
    let bookmarks: [ImportedBookmark]
    let history: [HistoryItem]
}

enum BrowserImportSource: String, CaseIterable, Identifiable {
    case chrome, arc, brave, edge, vivaldi, chromium, dia, helium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chrome: "Chrome"
        case .arc: "Arc"
        case .brave: "Brave"
        case .edge: "Edge"
        case .vivaldi: "Vivaldi"
        case .chromium: "Chromium"
        case .dia: "Dia"
        case .helium: "Helium"
        }
    }

    var userDataDirectory: URL {
        let relativePath = switch self {
        case .chrome: "Google/Chrome"
        case .arc: "Arc/User Data"
        case .brave: "BraveSoftware/Brave-Browser"
        case .edge: "Microsoft Edge"
        case .vivaldi: "Vivaldi"
        case .chromium: "Chromium"
        case .dia: "Dia/User Data"
        case .helium: "net.imput.helium"
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: true)
    }

    var bookmarkKey: String { "browserImport.profile.\(rawValue)" }
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
            case .unreadableHistory: "Lean couldn't read the browser History database. Check that you selected the browser data folder and try again."
            case .invalidPasswordCSV: "The password CSV needs URL, username, and password columns."
            case .invalidHistoryCSV: "The history CSV needs a URL column and can include title and timestamp columns."
            }
        }
    }

    static func readBookmarkExport(_ data: Data) throws -> [ImportedBookmark] {
        let bookmarks = decodeBookmarks(data)
        if !bookmarks.isEmpty { return bookmarks }
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
            let htmlBookmarks = decodeHTMLBookmarks(text)
            if !htmlBookmarks.isEmpty { return htmlBookmarks }
        }
        throw ImportError.invalidBookmarks
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
            let date = dateIndex.flatMap { row.indices.contains($0) ? parseDate(row[$0], chromium: header[$0] == "last_visit_time") : nil } ?? .distantPast
            return HistoryItem(url: url, title: title, timestamp: date)
        }
    }

    static func readProfiles(at userDataDirectory: URL) throws -> BrowserImportPreview {
        var folders = Set<URL>()
        folders.insert(userDataDirectory)
        if let enumerator = FileManager.default.enumerator(
            at: userDataDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let file as URL in enumerator {
                let depth = file.pathComponents.count - userDataDirectory.pathComponents.count
                if depth > 3 {
                    enumerator.skipDescendants()
                    continue
                }
                if file.lastPathComponent == "Bookmarks" || file.lastPathComponent == "History" {
                    folders.insert(file.deletingLastPathComponent())
                }
            }
        }
        let previews = try folders.sorted { $0.path < $1.path }.compactMap { folder -> BrowserImportPreview? in
            guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("Bookmarks").path)
                    || FileManager.default.fileExists(atPath: folder.appendingPathComponent("History").path) else { return nil }
            do { return try readProfile(at: folder) }
            catch ImportError.invalidProfile { return nil }
        }
        guard !previews.isEmpty else { throw ImportError.invalidProfile }
        var bookmarks: [ImportedBookmark] = []
        var seenBookmarks = Set<String>()
        var historyByURL: [String: HistoryItem] = [:]
        for preview in previews {
            for bookmark in preview.bookmarks where seenBookmarks.insert(bookmark.url.absoluteString).inserted {
                bookmarks.append(bookmark)
            }
            for item in preview.history {
                if historyByURL[item.url.absoluteString].map({ $0.timestamp >= item.timestamp }) != true {
                    historyByURL[item.url.absoluteString] = item
                }
            }
        }
        return BrowserImportPreview(bookmarks: bookmarks, history: historyByURL.values.sorted { $0.timestamp > $1.timestamp })
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
            let scheme = url.scheme?.lowercased() ?? "https"
            let port = (scheme == "https" && url.port == 443) || (scheme == "http" && url.port == 80) ? nil : url.port
            let originKey = "\(scheme)://\(host)\(port.map { ":\($0)" } ?? "")\u{1}\(username)"
            guard seen.insert(originKey).inserted else { continue }
            credentials.append(ImportedCredential(origin: url, username: username, password: row[passwordColumn]))
        }
        return PasswordCSVPreview(credentials: credentials, skippedRows: rows.count - credentials.count)
    }

    @discardableResult
    static func saveCredentials(_ credentials: [ImportedCredential]) -> (saved: Int, skipped: Int) {
        let saved = credentials.reduce(into: 0) { count, credential in
            if case .success = PasswordVault.save(
                origin: credential.origin,
                username: credential.username,
                password: credential.password
            ) {
                count += 1
            }
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

    static func decodeHTMLBookmarks(_ html: String) -> [ImportedBookmark] {
        let pattern = "(?i)<a\\s+[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)<\\/a>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        var seen = Set<String>()
        var result: [ImportedBookmark] = []
        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let rawURL = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: rawURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            if !seen.insert(url.absoluteString).inserted { continue }
            var rawTitle = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            rawTitle = rawTitle.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            if rawTitle.isEmpty { rawTitle = url.host ?? url.absoluteString }
            result.append(ImportedBookmark(title: rawTitle, url: url))
        }
        return result
    }

    private static func readHistory(at url: URL) throws -> [HistoryItem] {
        let snapshot = FileManager.default.temporaryDirectory.appendingPathComponent("Lean-history-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: snapshot) }
        try snapshotDatabase(at: url, to: snapshot)

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(snapshot.path, &database, SQLITE_OPEN_READONLY, nil)
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

    private static func snapshotDatabase(at sourceURL: URL, to destinationURL: URL) throws {
        var source: OpaquePointer?
        var destination: OpaquePointer?
        guard sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let source else {
            if let source { sqlite3_close(source) }
            throw ImportError.unreadableHistory
        }
        defer { sqlite3_close(source) }
        guard sqlite3_open_v2(destinationURL.path, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let destination else {
            if let destination { sqlite3_close(destination) }
            throw ImportError.unreadableHistory
        }
        defer { sqlite3_close(destination) }
        sqlite3_busy_timeout(source, 500)
        sqlite3_busy_timeout(destination, 500)
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw ImportError.unreadableHistory
        }
        var result = sqlite3_backup_step(backup, -1)
        var retries = 0
        while (result == SQLITE_BUSY || result == SQLITE_LOCKED) && retries < 4 {
            Thread.sleep(forTimeInterval: 0.05)
            result = sqlite3_backup_step(backup, -1)
            retries += 1
        }
        let finishResult = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finishResult == SQLITE_OK else { throw ImportError.unreadableHistory }
    }

    private static func parseDate(_ text: String, chromium: Bool) -> Date? {
        if let value = Double(text) {
            if chromium { return Date(timeIntervalSince1970: value / 1_000_000 - 11_644_473_600) }
            return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1_000 : value)
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
