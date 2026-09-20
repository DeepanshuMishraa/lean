import Testing
import Foundation
@testable import Lean

struct SettingsPopoverHistoryTests {
    @Test("openSettings with category sets selectedSettingsCategory")
    @MainActor
    func openSettingsSetsCategory() {
        let store = LeanStore()

        store.openSettings(category: .history)
        #expect(store.selectedSettingsCategory == .history)
        #expect(store.selectedTab?.isSettingsPage == true)

        store.openSettings(category: .appearance)
        #expect(store.selectedSettingsCategory == .appearance)
        #expect(store.selectedTab?.isSettingsPage == true)
    }

    @Test("History items are loaded and openHistoryItem loads target URL")
    @MainActor
    func openHistoryItemNavigates() {
        let store = LeanStore()
        let url = URL(string: "https://example.com")!
        let item = HistoryItem(url: url, title: "Example Domain")

        store.recordHistory(url: url, title: "Example Domain")
        #expect(store.historyItems.contains(where: { $0.url == url }))

        store.openHistoryItem(item, inNewTab: true)
        #expect(store.tabs.contains(where: { $0.url == url }))
    }
}
