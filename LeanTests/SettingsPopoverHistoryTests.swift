import Testing
import Foundation
@testable import Lean

struct SettingsPopoverHistoryTests {
    @Test("openSettings with category sets selectedSettingsCategory")
    @MainActor
    func openSettingsSetsCategory() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.openSettings(category: .history)
        #expect(store.selectedSettingsCategory == .history)
        #expect(store.selectedTab?.isSettingsPage == true)

        store.openSettings(category: .appearance)
        #expect(store.selectedSettingsCategory == .appearance)
        #expect(store.selectedTab?.isSettingsPage == true)
    }

    @Test("History items are loaded and openHistoryItem loads target URL")
    @MainActor
    func openHistoryItemNavigates() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://example.com")!
        let item = HistoryItem(url: url, title: "Example Domain")

        store.recordHistory(url: url, title: "Example Domain")
        #expect(store.historyItems.contains(where: { $0.url == url }))

        store.openHistoryItem(item, inNewTab: true)
        #expect(store.tabs.contains(where: { $0.url == url }))
    }

    @Test("Open tabs are restored from the persisted session on relaunch")
    @MainActor
    func sessionRestoresOpenTabs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Lean.sqlite3")

        let first = LeanStore(database: try AppDatabase(url: url))
        first.newTab(url: URL(string: "https://example.com")!, select: false)
        first.newTab(url: URL(string: "https://apple.com")!, select: true)
        first.saveSession()

        let second = LeanStore(database: try AppDatabase(url: url))
        #expect(second.tabs.compactMap(\.url).map(\.absoluteString) == ["https://example.com", "https://apple.com"])
        #expect(second.selectedTab?.url?.absoluteString == "https://apple.com")
    }
}
