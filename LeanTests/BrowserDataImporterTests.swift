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
        #expect(preview.history.first?.timestamp == Date(timeIntervalSince1970: 1_755_526_400))
    }

    @Test("A locked History costs the history, not the bookmarks next to it")
    func toleratesUnreadableHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bookmarks = #"{"roots":{"bookmark_bar":{"children":[{"type":"url","name":"Docs","url":"https://docs.example/"}]}}}"#
        try Data(bookmarks.utf8).write(to: directory.appendingPathComponent("Bookmarks"))
        try Data("not a database".utf8).write(to: directory.appendingPathComponent("History"))

        let preview = try BrowserDataImporter.readProfile(at: directory)
        #expect(preview.bookmarks.count == 1)
        #expect(preview.history.isEmpty)
        #expect(preview.historyIncomplete)
    }

    @Test("Corrupt History alone reports unreadable, not an empty profile")
    func corruptHistoryOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a database".utf8).write(to: directory.appendingPathComponent("History"))

        #expect(throws: BrowserDataImporter.ImportError.unreadableHistory) {
            try BrowserDataImporter.readProfile(at: directory)
        }
    }

    @Test("One bad profile does not sink the profiles that read fine")
    func isolatesFailingProfiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let good = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
        let bookmarks = #"{"roots":{"bookmark_bar":{"children":[{"type":"url","name":"Docs","url":"https://docs.example/"}]}}}"#
        try Data(bookmarks.utf8).write(to: good.appendingPathComponent("Bookmarks"))
        let bad = root.appendingPathComponent("Profile 1")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("not a database".utf8).write(to: bad.appendingPathComponent("History"))

        let preview = try BrowserDataImporter.readProfiles(at: root)
        #expect(preview.bookmarks.count == 1)
        #expect(preview.historyIncomplete)
    }

    @Test("Display paths point at the real home, not the sandbox container")
    func displayPaths() {
        let path = BrowserImportSource.helium.displayDataDirectory.path
        #expect(!path.contains("Containers"))
        #expect(path.hasSuffix("Library/Application Support/net.imput.helium"))
    }

    @Test("Arc grant covers the parent holding the sidebar")
    func arcGrantDirectory() {
        #expect(BrowserImportSource.arc.grantDirectory.lastPathComponent == "Arc")
        #expect(BrowserImportSource.chrome.grantDirectory.lastPathComponent == "Chrome")
        #expect(BrowserImportSource.helium.grantDirectory.lastPathComponent == "net.imput.helium")
    }

    @Test("Arc sidebar tabs decode from the alternating items list")
    func decodesArcSidebar() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sidebar = """
        {"sidebar": {"containers": [{"items": [
            "id-1",
            {"title": null, "childrenIds": [], "data": {"tab": {"savedURL": "https://example.com/pinned", "savedTitle": "Pinned Tab"}}},
            "id-2",
            {"title": "Named", "childrenIds": [], "data": {"tab": {"savedURL": "https://example.org/", "savedTitle": "Ignored"}}},
            "id-3",
            {"title": null, "childrenIds": [], "data": {"itemContainer": {"containerType": {}}}},
            "id-4",
            {"title": null, "childrenIds": [], "data": {"tab": {"savedURL": "ftp://files.example/x", "savedTitle": "Nope"}}}
        ]}]}}
        """
        try Data(sidebar.utf8).write(to: directory.appendingPathComponent("StorableSidebar.json"))

        let bookmarks = BrowserDataImporter.arcSidebarBookmarks(in: directory)
        #expect(bookmarks.count == 2)
        #expect(bookmarks[0].url.absoluteString == "https://example.com/pinned")
        #expect(bookmarks[0].title == "Pinned Tab")
        #expect(bookmarks[1].title == "Named")
    }

    @Test("Arc sidebar merges into profile scans without doubling")
    func mergesArcSidebar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let userData = root.appendingPathComponent("User Data/Default")
        try FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
        let bookmarks = #"{"roots":{"bookmark_bar":{"children":[{"type":"url","name":"Docs","url":"https://docs.example/"}]}}}"#
        try Data(bookmarks.utf8).write(to: userData.appendingPathComponent("Bookmarks"))
        let sidebar = """
        {"sidebar": {"containers": [{"items": [
            "id-1",
            {"title": null, "childrenIds": [], "data": {"tab": {"savedURL": "https://docs.example/", "savedTitle": "Same"}}},
            "id-2",
            {"title": null, "childrenIds": [], "data": {"tab": {"savedURL": "https://sidebar.example/", "savedTitle": "Sidebar Tab"}}}
        ]}]}}
        """
        try Data(sidebar.utf8).write(to: root.appendingPathComponent("StorableSidebar.json"))

        let preview = try BrowserDataImporter.readProfiles(at: root, source: .arc)
        #expect(preview.bookmarks.count == 2)
        #expect(preview.bookmarks.map(\.url.absoluteString).sorted() == ["https://docs.example/", "https://sidebar.example/"])
    }

    @Test("Browser data import discovers bookmarks across profiles")
    func discoversProfiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, host) in [("Default", "default.example"), ("Profile 1", "profile.example")] {
            let profile = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            let bookmarks = #"{"roots":{"bookmark_bar":{"children":[{"type":"url","name":"Docs","url":"https://\#(host)/"}]}}}"#
            try Data(bookmarks.utf8).write(to: profile.appendingPathComponent("Bookmarks"))
        }

        let preview = try BrowserDataImporter.readProfiles(at: root)
        #expect(preview.bookmarks.count == 2)
    }

    @Test("History CSV imports valid web addresses and timestamps")
    func parsesHistoryCSV() throws {
        let csv = "url,title,timestamp\nhttps://example.com,Example,1700000000\nhttps://millis.example,Millis,1700000000000\nfile:///tmp/page,Local,1700000000"
        let history = try BrowserDataImporter.readHistoryCSV(Data(csv.utf8))
        #expect(history.count == 2)
        #expect(history.first(where: { $0.title == "Millis" })?.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
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
