import Foundation
import Testing
@testable import Lean

struct TabDisplayModeTests {
    @MainActor
    @Test("TabDisplayMode provides proper raw values and titles")
    func tabDisplayModes() {
        #expect(TabDisplayMode.allCases.count == 3)
        #expect(TabDisplayMode.textOnly.rawValue == "textOnly")
        #expect(TabDisplayMode.iconOnly.rawValue == "iconOnly")
        #expect(TabDisplayMode.hybrid.rawValue == "hybrid")

        #expect(TabDisplayMode.textOnly.title == "Text Only")
        #expect(TabDisplayMode.iconOnly.title == "Icon Only")
        #expect(TabDisplayMode.hybrid.title == "Hybrid")
    }

    @MainActor
    @Test("LeanStore persists tab display mode")
    func leanStorePersistence() {
        let store = LeanStore()
        store.tabDisplayMode = .hybrid
        #expect(store.tabDisplayMode == .hybrid)
        #expect(UserDefaults.standard.string(forKey: "tabDisplayMode") == "hybrid")

        store.tabDisplayMode = .iconOnly
        #expect(store.tabDisplayMode == .iconOnly)
        #expect(UserDefaults.standard.string(forKey: "tabDisplayMode") == "iconOnly")

        store.tabDisplayMode = .textOnly
        #expect(store.tabDisplayMode == .textOnly)
        #expect(UserDefaults.standard.string(forKey: "tabDisplayMode") == "textOnly")
    }
}
