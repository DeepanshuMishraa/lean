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

struct StalledNavigationTests {
    @Test("A navigation is timed until it commits")
    @MainActor
    func stallClockClearsOnCommit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = directory.appendingPathComponent("page.html")
        try "<title>Page</title>".write(to: page, atomically: true, encoding: .utf8)

        let tab = LeanTab(dataStore: .nonPersistent(), initialURL: nil, adBlockingEnabled: false)
        tab.load(page)
        #expect(tab.uncommittedNavigationSince != nil)
        #expect(await waitUntil { tab.url == page && !tab.isLoading })
        #expect(tab.uncommittedNavigationSince == nil)
        tab.destroy()
    }

    @Test("WebKit's network process can be restarted, and pages load after it")
    @MainActor
    func networkProcessRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = directory.appendingPathComponent("page.html")
        try "<title>After</title>".write(to: page, atomically: true, encoding: .utf8)
        let dataStore = WKWebsiteDataStore.nonPersistent()

        #expect(NetworkProcess.restart(via: dataStore))

        let tab = LeanTab(dataStore: dataStore, initialURL: nil, adBlockingEnabled: false)
        tab.load(page)
        #expect(await waitUntil { tab.url == page && !tab.isLoading && tab.webView.title == "After" })
        tab.destroy()
    }
}
