import Foundation
import Testing
@testable import Lean

struct TabSwitcherSessionTests {
    @MainActor
    private func makeStore(with urls: [String]) throws -> (LeanStore, URL, [LeanTab]) {
        let (store, directory) = try makeIsolatedTestStore()
        var created: [LeanTab] = []
        for (index, raw) in urls.enumerated() {
            created.append(store.newTab(url: URL(string: raw)!, select: index == 0))
        }
        return (store, directory, created)
    }

    @Test("Commit selects the highlighted tab")
    @MainActor
    func commitSelectsNext() throws {
        let (store, directory, tabs) = try makeStore(with: [
            "https://a.example/", "https://b.example/", "https://c.example/",
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        store.startTabSwitcher()
        #expect(store.isTabSwitcherVisible)
        #expect(store.switcherSelectedIndex == 1)
        store.commitTabSwitcher()
        #expect(!store.isTabSwitcherVisible)
        #expect(store.selectedID == tabs[1].id)
    }

    @Test("Reverse start highlights the previous tab")
    @MainActor
    func reverseStart() throws {
        let (store, directory, tabs) = try makeStore(with: [
            "https://a.example/", "https://b.example/", "https://c.example/",
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        store.startTabSwitcher(reverse: true)
        #expect(store.switcherSelectedIndex == 2)
        store.commitTabSwitcher()
        #expect(store.selectedID == tabs[2].id)
    }

    @Test("Reordering mid-gesture still commits the highlighted tab")
    @MainActor
    func reorderMidGestureCommitsHighlightedTab() throws {
        let (store, directory, tabs) = try makeStore(with: [
            "https://a.example/", "https://b.example/", "https://c.example/",
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        // Highlight B…
        store.startTabSwitcher()
        #expect(store.switcherVisibleTabs[store.switcherSelectedIndex].id == tabs[1].id)
        // …then move B to the end before releasing.
        store.moveTab(id: tabs[1].id, toIndex: 2)
        // The rows and the highlight still agree, and committing lands on B.
        #expect(store.switcherVisibleTabs[store.switcherSelectedIndex].id == tabs[1].id)
        store.commitTabSwitcher()
        #expect(store.selectedID == tabs[1].id)
    }

    @Test("Closing the highlighted tab falls back instead of staying put")
    @MainActor
    func closeHighlightedTabFallsBack() throws {
        let (store, directory, tabs) = try makeStore(with: [
            "https://a.example/", "https://b.example/", "https://c.example/",
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        store.startTabSwitcher() // highlights B
        store.close(tabs[1])
        store.commitTabSwitcher()
        #expect(!store.isTabSwitcherVisible)
        #expect(store.selectedID == tabs[2].id)
    }

    @Test("Cancel keeps the current tab")
    @MainActor
    func cancelKeepsSelection() throws {
        let (store, directory, tabs) = try makeStore(with: [
            "https://a.example/", "https://b.example/",
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        store.startTabSwitcher()
        store.cancelTabSwitcher()
        #expect(!store.isTabSwitcherVisible)
        #expect(store.selectedID == tabs[0].id)
    }
}
