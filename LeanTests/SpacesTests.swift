import Foundation
import Testing
import WebKit
@testable import Lean

struct SpacesTests {
    @Test("A new space starts with its own tab and parks the tabs it left")
    @MainActor
    func switchingParksTabs() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.spaces.map(\.name) == ["Personal"])
        let personal = store.selectedSpaceID
        let personalTabs = store.tabs.map(\.id)

        store.addSpace()
        #expect(store.spaces.count == 2)
        #expect(store.selectedSpaceID != personal)
        #expect(store.tabs.count == 1)
        #expect(Set(store.tabs.map(\.id)).isDisjoint(with: personalTabs))

        store.switchToSpace(id: personal)
        #expect(store.tabs.map(\.id) == personalTabs)
        #expect(store.selectedID.map { personalTabs.contains($0) } == true)
    }

    @Test("Each space loads its pages into a data store of its own")
    @MainActor
    func separateWebsiteData() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let personalStore = try #require(store.tabs.first).webView.configuration.websiteDataStore

        store.addSpace()
        let workStore = try #require(store.tabs.first).webView.configuration.websiteDataStore
        #expect(personalStore !== workStore)

        _ = store.newTab()
        #expect(store.tabs.allSatisfy { $0.webView.configuration.websiteDataStore === workStore })
    }

    @Test("Spaces, the one in front, and each one's tabs survive a relaunch")
    @MainActor
    func persistsAcrossRelaunch() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = directory.appendingPathComponent("work.html")
        try "<title>Work</title>".write(to: page, atomically: true, encoding: .utf8)

        store.addSpace()
        let work = store.selectedSpaceID
        store.renameSpace(id: work, to: "Work")
        store.selectedTab?.load(page)
        store.flushPendingPersist()

        let database = try AppDatabase(url: directory.appendingPathComponent("Lean.sqlite3"))
        let relaunched = LeanStore(dataStore: .nonPersistent(), database: database)
        #expect(relaunched.spaces.map(\.name) == ["Personal", "Work"])
        #expect(relaunched.selectedSpaceID == work)
        #expect(relaunched.tabs.compactMap(\.url) == [page])
    }

    @Test("History, bookmarks and downloads belong to the space they were made in")
    @MainActor
    func separateBrowsingData() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let personal = store.selectedSpaceID
        let personalPage = try #require(URL(string: "https://personal.example/"))
        store.recordHistory(url: personalPage, title: "Personal")
        store.addBookmark(title: "Personal", url: personalPage)
        store.flushPendingPersist()
        store.downloadManager.beginDownload(fileName: "p.zip", sourceURL: nil, destinationURL: URL(fileURLWithPath: "/tmp/lean-p.zip"), totalBytes: 1)
        let personalDownloads = store.downloadManager

        store.addSpace()
        let work = store.selectedSpaceID
        #expect(store.historyItems.isEmpty)
        #expect(store.bookmarks.isEmpty)
        #expect(store.downloadManager !== personalDownloads)
        #expect(store.downloadManager.downloads.isEmpty)
        let workPage = try #require(URL(string: "https://work.example/"))
        store.recordHistory(url: workPage, title: "Work")

        store.switchToSpace(id: personal)
        #expect(store.historyItems.map(\.url) == [personalPage])
        #expect(store.bookmarks.map(\.url) == [personalPage])
        #expect(store.downloadManager === personalDownloads)

        let database = try AppDatabase(url: directory.appendingPathComponent("Lean.sqlite3"))
        store.switchToSpace(id: work)
        store.flushPendingPersist()
        let relaunched = LeanStore(dataStore: .nonPersistent(), database: database)
        #expect(relaunched.historyItems.map(\.url) == [workPage])
        #expect(relaunched.bookmarks.isEmpty)
    }

    @Test("Deleting a space closes its tabs and keeps the last space")
    @MainActor
    func deleteSpace() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let personal = store.selectedSpaceID
        store.addSpace()
        let extra = store.selectedSpaceID

        store.deleteSpace(id: extra)
        #expect(store.spaces.map(\.id) == [personal])
        #expect(store.selectedSpaceID == personal)
        #expect(!store.tabs.isEmpty)

        store.deleteSpace(id: personal)
        #expect(store.spaces.map(\.id) == [personal])
    }

    @Test("Switching to the adjacent space wraps around")
    @MainActor
    func adjacentSpaceWraps() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = store.selectedSpaceID
        store.addSpace()
        let second = store.selectedSpaceID

        store.switchToAdjacentSpace(forward: true)
        #expect(store.selectedSpaceID == first)
        store.switchToAdjacentSpace(forward: false)
        #expect(store.selectedSpaceID == second)
    }
}
