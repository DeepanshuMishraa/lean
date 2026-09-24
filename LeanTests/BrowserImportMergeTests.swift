import Foundation
import Testing
@testable import Lean

struct BrowserImportMergeTests {
    private func preview() -> BrowserImportPreview {
        BrowserImportPreview(
            bookmarks: [
                ImportedBookmark(title: "Docs", url: URL(string: "https://docs.example/")!),
                ImportedBookmark(title: "Blog", url: URL(string: "https://blog.example/")!),
            ],
            history: [
                HistoryItem(url: URL(string: "https://docs.example/")!, title: "Docs", timestamp: Date(timeIntervalSince1970: 1_700_000_000)),
            ]
        )
    }

    @Test("Re-importing the same browser adds nothing and overwrites nothing")
    @MainActor
    func reimportIsIdempotent() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = store.importBrowserData(preview())
        #expect(first == (2, 1))
        let second = store.importBrowserData(preview())
        #expect(second == (0, 0))
        #expect(store.importedBookmarks.count == 2)
        #expect(store.historyItems.count == 1)
        #expect(store.historyItems[0].title == "Docs")
    }

    @Test("Imports from several browsers merge into one library")
    @MainActor
    func mergesMultipleBrowsers() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = store.importBrowserData(preview())
        let other = BrowserImportPreview(
            bookmarks: [
                ImportedBookmark(title: "Docs Mirror", url: URL(string: "https://docs.example/")!),
                ImportedBookmark(title: "News", url: URL(string: "https://news.example/")!),
            ],
            history: []
        )
        let second = store.importBrowserData(other)
        // docs.example was already there under its first title — kept, not doubled, not renamed.
        #expect(second == (1, 0))
        #expect(store.importedBookmarks.count == 3)
        #expect(store.importedBookmarks.first { $0.url.absoluteString == "https://docs.example/" }?.title == "Docs")
    }

    @Test("A later import never evicts the user's own history")
    @MainActor
    func preservesUserHistory() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.recordHistory(url: URL(string: "https://mine.example/")!, title: "Mine")
        _ = store.importBrowserData(preview())
        #expect(store.historyItems.contains(where: { $0.url.absoluteString == "https://mine.example/" }))
        #expect(store.historyItems.contains(where: { $0.url.absoluteString == "https://docs.example/" }))
    }

    @Test("Credential import never overwrites what the vault already keeps")
    func neverOverwrites() {
        // Both are already in the vault (possibly with newer passwords) —
        // the import must skip, not clobber. All-true means no keychain
        // write is attempted at all, keeping this test hermetic.
        var consulted: [String] = []
        let credentials = [
            ImportedCredential(origin: URL(string: "https://example.com/login")!, username: "alice", password: "old"),
            ImportedCredential(origin: URL(string: "https://new.example/")!, username: "bob", password: "fresh"),
        ]
        let result = BrowserDataImporter.saveCredentials(credentials, alreadySaved: {
            consulted.append($0.username)
            return true
        })
        #expect(consulted == ["alice", "bob"])
        #expect(result.saved == 0)
        #expect(result.skipped == 2)
    }
}
