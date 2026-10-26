import Foundation
import Testing
import WebKit
@testable import Lean

@MainActor
private func waitUntil(_ seconds: Double = 15, _ condition: @escaping @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

/// A page on disk, so loads need no network.
private func makePage(_ title: String) throws -> (page: URL, directory: URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let page = directory.appendingPathComponent("page.html")
    try "<title>\(title)</title><a id=link href=\"page.html\">link</a>".write(to: page, atomically: true, encoding: .utf8)
    return (page, directory)
}

/// Closing a tab must free it and its web view: anything left holding either
/// (a script message handler, an observation, a closure) keeps a whole
/// WebContent process's worth of memory alive for the rest of the session.
struct MemoryLifecycleTests {
    @Test("A destroyed tab frees itself and its web view")
    @MainActor
    func destroyedTabIsFreed() async throws {
        let (page, directory) = try makePage("Page")
        defer { try? FileManager.default.removeItem(at: directory) }

        weak var weakTab: LeanTab?
        weak var weakWebView: WKWebView?
        do {
            let tab = LeanTab(dataStore: .nonPersistent(), initialURL: nil, adBlockingEnabled: false)
            tab.load(page)
            #expect(await waitUntil { tab.url == page && !tab.isLoading })
            weakTab = tab
            weakWebView = tab.webView
            tab.destroy()
        }

        #expect(await waitUntil(5) { weakTab == nil && weakWebView == nil })
    }

    @Test("A tab closed from the store is freed")
    @MainActor
    func closedTabIsFreed() async throws {
        let (store, storeDirectory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let (page, directory) = try makePage("Closed")
        defer { try? FileManager.default.removeItem(at: directory) }

        weak var weakTab: LeanTab?
        weak var weakWebView: WKWebView?
        do {
            let tab = store.newTab(url: page)
            #expect(await waitUntil { tab.url == page && !tab.isLoading })
            weakTab = tab
            weakWebView = tab.webView
            store.close(tab)
        }

        #expect(await waitUntil(5) { weakTab == nil && weakWebView == nil })
    }

    @Test("A closed peek frees its page once it has animated away")
    @MainActor
    func closedPeekIsFreed() async throws {
        let (store, storeDirectory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let (page, directory) = try makePage("Peek")
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = store.newTab(url: page)
        #expect(await waitUntil { source.url == page && !source.isLoading })

        weak var weakPeek: LeanTab?
        do {
            store.peek(page, from: source)
            weakPeek = store.peekTab
            #expect(weakPeek != nil)
            store.closePeek()
        }

        #expect(await waitUntil(5) { store.peekTab == nil && weakPeek == nil })
    }

    @Test("A store whose window closed frees itself and its tabs")
    @MainActor
    func closedStoreIsFreed() async throws {
        let (page, directory) = try makePage("Store")
        defer { try? FileManager.default.removeItem(at: directory) }

        weak var weakStore: LeanStore?
        weak var weakTab: LeanTab?
        var storeDirectory: URL?
        do {
            let (store, storeDir) = try makeIsolatedTestStore()
            storeDirectory = storeDir
            let tab = store.newTab(url: page)
            #expect(await waitUntil { tab.url == page && !tab.isLoading })
            weakStore = store
            weakTab = tab
            for open in store.tabs { store.close(open) }
        }
        defer { storeDirectory.map { try? FileManager.default.removeItem(at: $0) } }

        #expect(await waitUntil(5) { weakStore == nil && weakTab == nil })
    }

    @Test("A background tab makes no page until it is first shown")
    @MainActor
    func backgroundTabDefersItsPage() async throws {
        let (store, storeDirectory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let (page, directory) = try makePage("Background")
        defer { try? FileManager.default.removeItem(at: directory) }

        let tab = store.newTab(url: page, select: false)
        #expect(tab.url == page)
        #expect(!tab.hasWebView)
        #expect(!tab.isLoading)

        // Showing it is what makes the page (the view asks for `webView`).
        _ = tab.webView
        #expect(tab.hasWebView)
        #expect(await waitUntil { tab.url == page && !tab.isLoading })
    }

    @Test("Restoring a session loads only the tab in front")
    @MainActor
    func sessionRestoreLoadsOnlySelectedTab() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pages = try (0..<3).map { try makePage("Restored \($0)") }
        defer { pages.forEach { try? FileManager.default.removeItem(at: $0.directory) } }

        struct Session: Encodable {
            let urls: [String]
            let selectedIndex: Int
            let pinnedIndices: [Int]
        }

        let database = try AppDatabase(url: directory.appendingPathComponent("Lean.sqlite3"))
        try database.set(
            Session(urls: pages.map(\.page.absoluteString), selectedIndex: 1, pinnedIndices: []),
            forKey: "browserSession_v1"
        ).get()

        let store = LeanStore(dataStore: .nonPersistent(), database: database)
        defer { store.tearDown() }
        #expect(store.tabs.count == 3)

        let selected = store.tabs[1]
        #expect(await waitUntil { selected.hasWebView && !selected.isLoading })
        #expect(store.tabs[0].url == pages[0].page)
        #expect(!store.tabs[0].hasWebView)
        #expect(store.tabs[2].url == pages[2].page)
        #expect(!store.tabs[2].hasWebView)
    }

    @Test("A closed window frees a split tab that lists itself")
    @MainActor
    func windowCloseFreesSplitTab() async throws {
        let (store, storeDirectory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let (page, directory) = try makePage("Split")
        defer { try? FileManager.default.removeItem(at: directory) }

        weak var weakParent: LeanTab?
        weak var weakPane: LeanTab?
        do {
            let parent = store.newTab(url: page)
            let pane = store.newTab(url: page, select: false)
            store.openTabAsSplit(pane)
            #expect(parent.splitTabs.count == 2)
            #expect(parent.splitTabs.first === parent)
            weakParent = parent
            weakPane = pane
        }

        store.tearDown()
        #expect(await waitUntil(5) { weakParent == nil && weakPane == nil })
    }

    @Test("Reopening a closed window brings its tabs back")
    @MainActor
    func reopeningWindowRestoresSession() async throws {
        let (store, storeDirectory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let (front, frontDirectory) = try makePage("Front")
        defer { try? FileManager.default.removeItem(at: frontDirectory) }
        let (behind, behindDirectory) = try makePage("Behind")
        defer { try? FileManager.default.removeItem(at: behindDirectory) }

        store.newTab(url: front)
        store.newTab(url: behind, select: false)
        #expect(await waitUntil { store.tabs.contains { $0.url == behind } })

        store.tearDown()
        #expect(store.tabs.isEmpty)

        store.restoreSessionIfNeeded()
        #expect(store.tabs.count == 2)
        #expect(store.tabs[0].url == front)
        #expect(store.tabs[1].url == behind)
        #expect(store.tabs[0].id == store.selectedID)
        // The tab in front loads; the one behind is a title until shown.
        #expect(await waitUntil { store.tabs[0].hasWebView && !store.tabs[0].isLoading })
        #expect(!store.tabs[1].hasWebView)
    }
}
