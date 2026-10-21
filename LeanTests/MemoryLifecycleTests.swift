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
}
