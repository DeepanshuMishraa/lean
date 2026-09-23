import Foundation
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

    @Test("History CSV imports valid web addresses and timestamps")
    func parsesHistoryCSV() throws {
        let csv = "url,title,timestamp\nhttps://example.com,Example,1700000000\nfile:///tmp/page,Local,1700000000"
        let history = try BrowserDataImporter.readHistoryCSV(Data(csv.utf8))
        #expect(history.count == 1)
        #expect(history.first?.title == "Example")
        #expect(history.first?.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Password CSV requires the expected credential columns")
    func rejectsUnrecognizedCSV() {
        #expect(throws: BrowserDataImporter.ImportError.invalidPasswordCSV) {
            try BrowserDataImporter.readPasswordCSV(Data("site,account,secret\na,b,c".utf8))
        }
    }
}
