import Foundation
import SQLite3
import Testing
@testable import Lean

struct BrowserDataImporterTests {
    @Test("Password CSV handles quoted commas and ignores invalid rows")
    func parsesPasswordCSV() throws {
        let csv = "\u{feff}name,url,username,password,note\nExample,https://Example.com/login,alice,\"a,b\",\"line one\nline two\"\nDuplicate,https://example.com/other,alice,other,\nBad,not a URL,bob,nope,"
        let preview = try BrowserDataImporter.readPasswordCSV(Data(csv.utf8))
        #expect(preview.credentials.count == 1)
        #expect(preview.skippedRows == 2)
        #expect(preview.credentials[0].host == "example.com")
        #expect(preview.credentials[0].username == "alice")
        #expect(preview.credentials[0].password == "a,b")
    }

    @Test("Chromium profile import reads nested bookmark entries")
    func readsProfileBookmarks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bookmarks = #"{"roots":{"bookmark_bar":{"children":[{"type":"folder","name":"Work","children":[{"type":"url","name":"Docs","url":"https://docs.example/"}]}]}}}"#
        try Data(bookmarks.utf8).write(to: directory.appendingPathComponent("Bookmarks"))

        let preview = try BrowserDataImporter.readProfile(at: directory)
        #expect(preview.bookmarks.count == 1)
        #expect(preview.bookmarks.first?.title == "Docs")
        #expect(preview.bookmarks.first?.url.absoluteString == "https://docs.example/")
        #expect(preview.history.isEmpty)
    }

    @Test("History import snapshots an openable Chromium database")
    func readsHistoryDatabase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var database: OpaquePointer?
        #expect(sqlite3_open(directory.appendingPathComponent("History").path, &database) == SQLITE_OK)
        guard let database else { return }
        defer { sqlite3_close(database) }
        let schema = "CREATE TABLE urls(url TEXT, title TEXT, last_visit_time INTEGER, hidden INTEGER, visit_count INTEGER); INSERT INTO urls VALUES('https://helium.example/','Helium',13400000000000000,0,1);"
        #expect(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK)

        let preview = try BrowserDataImporter.readProfile(at: directory)
        #expect(preview.history.count == 1)
        #expect(preview.history.first?.title == "Helium")
        #expect(preview.history.first?.url.host == "helium.example")
    }

    @Test("Helium import uses its macOS Chromium data directory")
    func heliumDataDirectory() {
        #expect(BrowserImportSource.helium.title == "Helium")
        #expect(BrowserImportSource.helium.userDataDirectory.lastPathComponent == "net.imput.helium")
    }

    @Test("Browser data import discovers bookmarks across profiles")
    func discoversProfiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bookmarks = #"{"roots":{"bookmark_bar":{"children":[{"type":"url","name":"Docs","url":"https://docs.example/"}]}}}"#
        for name in ["Default", "Profile 1"] {
            let profile = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            try Data(bookmarks.utf8).write(to: profile.appendingPathComponent("Bookmarks"))
        }

        let preview = try BrowserDataImporter.readProfiles(at: root)
        #expect(preview.bookmarks.count == 1)
        #expect(preview.bookmarks.first?.url.absoluteString == "https://docs.example/")
    }

    @Test("History CSV imports valid web addresses and timestamps")
    func parsesHistoryCSV() throws {
        let csv = "url,title,timestamp\nhttps://example.com,Example,1700000000\nfile:///tmp/page,Local,1700000000"
        let history = try BrowserDataImporter.readHistoryCSV(Data(csv.utf8))
        #expect(history.count == 1)
        #expect(history.first?.title == "Example")
        #expect(history.first?.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Password CSV keeps credentials for different origins separate")
    func separatesPasswordOrigins() throws {
        let csv = "url,username,password\nhttps://example.com,alice,one\nhttp://example.com,alice,two\nhttps://sub.example.com,alice,three"
        let preview = try BrowserDataImporter.readPasswordCSV(Data(csv.utf8))
        #expect(preview.credentials.count == 3)
        #expect(preview.credentials.map(\.origin.scheme) == ["https", "http", "https"])
    }

    @Test("Password CSV requires the expected credential columns")
    func rejectsUnrecognizedCSV() {
        #expect(throws: BrowserDataImporter.ImportError.invalidPasswordCSV) {
            try BrowserDataImporter.readPasswordCSV(Data("site,account,secret\na,b,c".utf8))
        }
    }
}
