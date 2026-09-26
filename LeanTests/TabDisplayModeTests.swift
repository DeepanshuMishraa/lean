import Foundation
import SwiftUI
import Testing
@testable import Lean

private func temporaryDatabase() throws -> (AppDatabase, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (try AppDatabase(url: directory.appendingPathComponent("Lean.sqlite3")), directory)
}

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
    func leanStorePersistence() throws {
        let (database, directory) = try temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LeanStore(database: database)

        store.tabDisplayMode = .hybrid
        #expect(store.tabDisplayMode == .hybrid)
        #expect(try database.value(String.self, forKey: "tabDisplayMode").get() == "hybrid")

        store.tabDisplayMode = .iconOnly
        #expect(store.tabDisplayMode == .iconOnly)
        #expect(try database.value(String.self, forKey: "tabDisplayMode").get() == "iconOnly")

        store.tabDisplayMode = .textOnly
        #expect(store.tabDisplayMode == .textOnly)
        #expect(try database.value(String.self, forKey: "tabDisplayMode").get() == "textOnly")
    }

    @MainActor
    @Test("LeanStore dismissInlineURLEditing resets state and frames")
    func dismissInlineURLEditing() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.isInlineURLEditing = true
        store.inlineURLBarFrame = CGRect(x: 10, y: 10, width: 200, height: 30)
        store.inlineSuggestionsFrame = CGRect(x: 10, y: 40, width: 200, height: 100)

        store.dismissInlineURLEditing()

        #expect(store.isInlineURLEditing == false)
        #expect(store.inlineURLBarFrame == .zero)
        #expect(store.inlineSuggestionsFrame == .zero)
    }

    @MainActor
    @Test("LeanStore persists window border settings")
    func windowBorderPersistence() throws {
        let (database, directory) = try temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LeanStore(database: database)

        store.enableWindowBorder = true
        #expect(store.enableWindowBorder == true)
        #expect(try database.value(Bool.self, forKey: "enableWindowBorder").get() == true)

        store.windowBorderWidth = 12.0
        #expect(store.windowBorderWidth == 12.0)
        #expect(try database.value(Double.self, forKey: "windowBorderWidth").get() == 12.0)

        // Zen mode persistence and distinctness from window border
        store.enableZenMode = true
        #expect(store.enableZenMode == true)
        #expect(try database.value(Bool.self, forKey: "enableZenMode").get() == true)

        store.enableZenMode = false
        #expect(store.enableZenMode == false)
        #expect(try database.value(Bool.self, forKey: "enableZenMode").get() == false)

        // Predefined light and dark colors for window frame
        store.theme = .light
        #expect(store.effectiveZenColor == LeanStore.zenModeLightColor)

        store.theme = .dark
        #expect(store.effectiveZenColor == LeanStore.zenModeDarkColor)
    }

    @Test("Color hex parsing and serialization roundtrips")
    func colorHexRoundtrip() {
        let color = Color(hex: "#D17A60")
        #expect(color.toHex().uppercased() == "#D17A60")

        let darkColor = Color(hex: "#2C2D32")
        #expect(darkColor.toHex().uppercased() == "#2C2D32")
    }

    @Test("AdaptiveFrameTheme adapts contrast dynamically across light, pastel, and dark colors")
    func adaptiveFrameThemeContrasts() {
        let baseDarkTheme = ThemeColors(isDark: true)
        let baseLightTheme = ThemeColors(isDark: false)

        // 1. Periwinkle (pastel from user screenshot: #7980C2) -> should be light surface with dark ink text/icons
        let periwinkleTheme = AdaptiveFrameTheme(
            isBorderEnabled: true,
            frameColor: Color(hex: "#7980C2"),
            baseThemeColors: baseDarkTheme,
            isBaseDark: true
        )
        #expect(periwinkleTheme.isFrameLight == true)
        #expect(periwinkleTheme.effectiveIsDark == false)
        #expect(periwinkleTheme.cardCornerRadius == 10)

        // 2. Pure White -> should be light surface
        let whiteTheme = AdaptiveFrameTheme(
            isBorderEnabled: true,
            frameColor: Color.white,
            baseThemeColors: baseDarkTheme,
            isBaseDark: true
        )
        #expect(whiteTheme.isFrameLight == true)
        #expect(whiteTheme.effectiveIsDark == false)

        // 3. Charcoal (#2C2D32) -> should be dark surface with luminous white text/icons
        let charcoalTheme = AdaptiveFrameTheme(
            isBorderEnabled: true,
            frameColor: Color(hex: "#2C2D32"),
            baseThemeColors: baseLightTheme,
            isBaseDark: false
        )
        #expect(charcoalTheme.isFrameLight == false)
        #expect(charcoalTheme.effectiveIsDark == true)

        // 4. Obsidian (#16161A) -> should be dark surface
        let obsidianTheme = AdaptiveFrameTheme(
            isBorderEnabled: true,
            frameColor: Color(hex: "#16161A"),
            baseThemeColors: baseDarkTheme,
            isBaseDark: true
        )
        #expect(obsidianTheme.isFrameLight == false)
        #expect(obsidianTheme.effectiveIsDark == true)

        // 5. Disabled border -> delegates to base theme
        let disabledBorderTheme = AdaptiveFrameTheme(
            isBorderEnabled: false,
            frameColor: Color(hex: "#7980C2"),
            baseThemeColors: baseDarkTheme,
            isBaseDark: true
        )
        #expect(disabledBorderTheme.cardCornerRadius == 0)
        #expect(disabledBorderTheme.effectiveIsDark == true)
    }

    @MainActor
    @Test("ToolbarItemType and LeanStore customizer persistence")
    func toolbarCustomizerTests() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(ToolbarItemType.allCases.count == 9)

        // Reset to default
        store.resetToolbarItems()
        #expect(store.shownToolbarItems.count == 9)
        #expect(store.hiddenToolbarItems.isEmpty)
        #expect(store.isToolbarItemShown(.bookmarks) == true)

        // Hide an item
        store.hideToolbarItem(.reload)
        #expect(store.isToolbarItemShown(.reload) == false)
        #expect(store.shownToolbarItems.contains(.reload) == false)
        #expect(store.hiddenToolbarItems.contains(.reload) == true)

        // Show it back
        store.showToolbarItem(.reload)
        #expect(store.isToolbarItemShown(.reload) == true)
        #expect(store.shownToolbarItems.contains(.reload) == true)
        #expect(store.hiddenToolbarItems.contains(.reload) == false)

        // Toggle an item
        store.toggleToolbarItem(.themeToggle)
        #expect(store.isToolbarItemShown(.themeToggle) == false)
        store.toggleToolbarItem(.themeToggle)
        #expect(store.isToolbarItemShown(.themeToggle) == true)

        // Move with id
        store.moveToolbarItem(withId: "settings", toShown: false)
        #expect(store.isToolbarItemShown(.settings) == false)
        store.moveToolbarItem(withId: "settings", toShown: true)
        #expect(store.isToolbarItemShown(.settings) == true)
    }

    @MainActor
    @Test("In-Tab Settings page navigation and address resolution")
    func inTabSettingsTests() throws {
        // Address resolution
        #expect(AddressResolver.resolve("settings")?.absoluteString == "lean://settings")
        #expect(AddressResolver.resolve("lean://settings")?.absoluteString == "lean://settings")
        #expect(AddressResolver.resolve("about:settings")?.absoluteString == "lean://settings")

        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.openSettings()

        // Should have a selected tab with settings
        guard let tab = store.selectedTab else {
            Issue.record("Expected selected tab")
            return
        }

        #expect(tab.isSettingsPage == true)
        #expect(tab.displayTitle(isSelected: true) == "Settings")
        #expect(tab.displayTitle(isSelected: false) == "Settings")

        // Calling openSettings again switches to existing tab
        let countBefore = store.tabs.count
        store.openSettings()
        #expect(store.tabs.count == countBefore)
        #expect(store.selectedID == tab.id)
    }

    @MainActor
    @Test("HistoryItem recording, deletion, and clear management")
    func historyManagementTests() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.clearHistory()
        #expect(store.historyItems.isEmpty)
        #expect(store.visitedHistory.isEmpty)

        let url1 = URL(string: "https://apple.com")!
        let url2 = URL(string: "https://github.com")!

        store.recordHistory(url: url1, title: "Apple")
        store.recordHistory(url: url2, title: "GitHub")

        #expect(store.historyItems.count == 2)
        #expect(store.historyItems.first?.title == "GitHub")
        #expect(store.visitedHistory.count == 2)
        #expect(store.visitedHistory.first?.title == "GitHub")

        // Ignores lean:// internal URLs
        let internalURL = URL(string: "lean://settings")!
        store.recordHistory(url: internalURL, title: "Settings")
        #expect(store.historyItems.count == 2)

        // Deleting individual item
        if let first = store.historyItems.first {
            store.deleteHistoryItem(id: first.id)
            #expect(store.historyItems.count == 1)
            #expect(store.historyItems.first?.title == "Apple")
        }

        // Clear history
        store.clearHistory()
        #expect(store.historyItems.isEmpty)
        #expect(store.visitedHistory.isEmpty)
    }

    @MainActor
    @Test("TabLayout enum and LeanStore persistence")
    func tabLayoutTests() throws {
        #expect(TabLayout.allCases.count == 2)
        #expect(TabLayout.top.rawValue == "top")
        #expect(TabLayout.sidebar.rawValue == "sidebar")
        #expect(TabLayout.top.title == "Top of Window")
        #expect(TabLayout.sidebar.title == "Sidebar")

        let (database, directory) = try temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LeanStore(database: database)

        #expect(store.tabLayout == .top)

        // Switching to sidebar enforces enableWindowBorder = true
        store.enableWindowBorder = false
        store.tabLayout = .sidebar
        #expect(store.tabLayout == .sidebar)
        #expect(store.enableWindowBorder == true)
        #expect(try database.value(String.self, forKey: "tabLayout").get() == "sidebar")

        // While in sidebar layout, frame mode cannot be disabled
        store.enableWindowBorder = false
        #expect(store.enableWindowBorder == true)

        // Toggling sidebar collapse
        #expect(store.isSidebarCollapsed == false)
        store.toggleSidebar()
        #expect(store.isSidebarCollapsed == true)
        #expect(try database.value(Bool.self, forKey: "isSidebarCollapsed").get() == true)
        store.toggleSidebar()
        #expect(store.isSidebarCollapsed == false)

        // Switching back to top allows toggling window border
        store.tabLayout = .top
        #expect(store.tabLayout == .top)
        #expect(try database.value(String.self, forKey: "tabLayout").get() == "top")
        store.enableWindowBorder = false
        #expect(store.enableWindowBorder == false)
    }

    @MainActor
    @Test("Sidebar shortcuts and toggle behavior")
    func sidebarShortcutsTests() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let action = ShortcutAction.toggleSidebar
        #expect(action.title == "Toggle Sidebar")
        #expect(action.defaultShortcut.key == "s")
        #expect(action.defaultShortcut.modifiers == ["command"])

        #expect(store.isSidebarCollapsed == false)
        action.performAction(in: store)
        #expect(store.isSidebarCollapsed == true)
        action.performAction(in: store)
        #expect(store.isSidebarCollapsed == false)

        // Toggle frame shortcut cannot turn off border when in sidebar mode
        store.tabLayout = .sidebar
        #expect(store.enableWindowBorder == true)
        ShortcutAction.toggleFrame.performAction(in: store)
        #expect(store.enableWindowBorder == true)
    }

    @MainActor
    @Test("Tab pinning, ordering, persistence, and move boundaries")
    func tabPinningAndReorderingTests() throws {
        let (database, directory) = try temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LeanStore(database: database)

        let tab1 = store.newTab(url: URL(string: "https://example.com")!, select: false)
        let tab2 = store.newTab(url: URL(string: "https://apple.com")!, select: false)
        let tab3 = store.newTab(url: URL(string: "https://news.ycombinator.com")!, select: true)

        #expect(store.pinnedTabs.isEmpty)
        #expect(store.unpinnedTabs.count == 4) // including initial tab

        // Pin tab2
        store.togglePin(tab: tab2)
        #expect(tab2.isPinned)
        #expect(store.pinnedTabs.map(\.id) == [tab2.id])
        #expect(store.tabs.first?.id == tab2.id)

        // Pin tab3
        store.togglePin(tab: tab3)
        #expect(tab3.isPinned)
        #expect(store.pinnedTabs.map(\.id) == [tab2.id, tab3.id])

        // Verify session persistence of pinned status
        store.saveSession()

        let restoredStore = LeanStore(database: database)
        #expect(restoredStore.pinnedTabs.count == 2)
        #expect(restoredStore.pinnedTabs[0].url?.absoluteString == "https://apple.com")
        #expect(restoredStore.pinnedTabs[1].url?.absoluteString == "https://news.ycombinator.com")
        #expect(restoredStore.unpinnedTabs.contains { $0.url?.absoluteString == "https://example.com" })

        // Test unpinning
        store.togglePin(tab: tab2)
        #expect(!tab2.isPinned)
        #expect(store.pinnedTabs.map(\.id) == [tab3.id])

        // Test moveTab boundaries: pinned tab cannot move past pinned section
        store.togglePin(tab: tab1) // Now tab3 and tab1 are pinned
        #expect(store.pinnedTabs.count == 2)
        let pinned1 = store.pinnedTabs[0]
        let pinned2 = store.pinnedTabs[1]

        // Reordering pinned tabs
        store.moveTab(id: pinned1.id, toIndex: 1)
        #expect(store.pinnedTabs.map(\.id) == [pinned2.id, pinned1.id])

        // Moving unpinned tab cannot move into pinned territory
        let unpinned = store.unpinnedTabs[0]
        store.moveTab(id: unpinned.id, toIndex: 0)
        // Destination was clamped to at least pinnedCount (2)
        #expect(!store.pinnedTabs.map(\.id).contains(unpinned.id))
    }

    @MainActor
    @Test("Pin tab shortcut Cmd+P and empty tab rejection")
    func pinShortcutTests() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let action = ShortcutAction.togglePinTab
        #expect(action.group == .tabs)
        #expect(action.title == "Pin / Unpin Tab")
        #expect(action.defaultShortcut.key == "p")
        #expect(action.defaultShortcut.modifiers == ["command"])

        // An empty tab cannot be pinned via shortcut or method
        let emptyTab = store.newTab(url: nil, select: true)
        action.performAction(in: store)
        #expect(!emptyTab.isPinned)
        #expect(store.pinnedTabs.isEmpty)

        store.togglePin(tab: emptyTab)
        #expect(!emptyTab.isPinned)
        #expect(store.pinnedTabs.isEmpty)

        // A tab with a URL can be pinned via shortcut
        let webTab = store.newTab(url: URL(string: "https://example.com")!, select: true)
        action.performAction(in: store)
        #expect(webTab.isPinned)
        #expect(store.pinnedTabs.map(\.id) == [webTab.id])

        // Toggling via shortcut unpins it
        action.performAction(in: store)
        #expect(!webTab.isPinned)
        #expect(store.pinnedTabs.isEmpty)
    }

    @MainActor
    @Test("Split tabs: open, add up to 4, separate, and close pane")
    func splitTabTests() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Shortcut definitions
        let openAction = ShortcutAction.openSplitTab
        #expect(openAction.group == .tabs)
        #expect(openAction.title == "Open as Split")
        #expect(openAction.defaultShortcut.key == "s")
        #expect(openAction.defaultShortcut.modifiers.contains("option"))
        #expect(openAction.defaultShortcut.modifiers.contains("command"))

        let separateAction = ShortcutAction.separateSplitTabs
        #expect(separateAction.group == .tabs)
        #expect(separateAction.title == "Separate Split Tabs")

        // Initial tab
        let tab1 = store.newTab(url: URL(string: "https://lean.dev")!, select: true)
        #expect(!tab1.isSplit)
        #expect(tab1.splitTabs.isEmpty)

        // 1. Open as split
        store.openTabAsSplit(tab1)
        #expect(tab1.isSplit)
        #expect(tab1.splitTabs.count == 2)
        #expect(tab1.activeSplitIndex == 1)
        #expect(tab1.splitTabs[0].id == tab1.id)

        // 2. Add 3rd and 4th tab to split
        let tab2 = store.newTab(url: URL(string: "https://apple.com")!, select: false)
        let tab3 = store.newTab(url: URL(string: "https://github.com")!, select: false)
        let tab4 = store.newTab(url: URL(string: "https://news.ycombinator.com")!, select: false)

        store.select(tab: tab1)
        store.addTabToActiveSplit(tab2)
        #expect(tab1.splitTabs.count == 3)
        #expect(!store.tabs.contains(where: { $0.id == tab2.id }))

        store.addTabToActiveSplit(tab3)
        #expect(tab1.splitTabs.count == 4)
        #expect(!store.tabs.contains(where: { $0.id == tab3.id }))

        // 3. Max 4 split tabs constraint: cannot add 5th tab
        store.addTabToActiveSplit(tab4)
        #expect(tab1.splitTabs.count == 4)
        #expect(store.tabs.contains(where: { $0.id == tab4.id }))

        // 4. Close a pane in the 4-way split: it pops out to the row,
        // the tab itself stays open.
        let paneToClose = tab1.splitTabs[2]
        store.closeSplitPane(in: tab1, pane: paneToClose)
        #expect(tab1.splitTabs.count == 3)
        #expect(!tab1.splitTabs.contains(where: { $0.id == paneToClose.id }))
        #expect(store.tabs.contains(where: { $0.id == paneToClose.id }))

        // 4b. Closing down to one pane collapses the split, keeping every
        // tab open — nothing is ever destroyed.
        let openIDs = Set(store.tabs.map(\.id) + tab1.splitTabs.map(\.id))
        let splitIDs = tab1.splitTabs.map(\.id)
        while tab1.splitTabs.count > 1 {
            store.closeSplitPane(in: tab1, pane: tab1.splitTabs.last!)
        }
        #expect(!tab1.isSplit)
        #expect(tab1.splitTabs.isEmpty)
        #expect(Set(store.tabs.map(\.id)) == openIDs)
        for id in splitIDs {
            #expect(store.tabs.contains(where: { $0.id == id }))
        }

        // 5. Separate remaining split tabs back to top level
        store.separateSplitTabs(tab1)
        #expect(!tab1.isSplit)
        #expect(tab1.splitTabs.isEmpty)
        #expect(store.tabs.count >= 3)
    }

    @MainActor
    @Test("Onboarding: launch, complete, and replay flow")
    func onboardingTests() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Start onboarding manually
        store.startOnboarding()
        #expect(store.isOnboardingPresented == true)

        // Completing onboarding
        store.completeOnboarding()
        #expect(store.hasCompletedOnboarding == true)
        #expect(store.isOnboardingPresented == false)

        // Step definitions
        #expect(OnboardingStep.allCases.count == 6)
        #expect(OnboardingStep.story.title == "The Story")
        #expect(OnboardingStep.features.title == "Features")
        #expect(OnboardingStep.selectBrowser.title == "Import")
        #expect(OnboardingStep.checklist.title == "Customize")
        #expect(OnboardingStep.importing.title == "Migrating")
        #expect(OnboardingStep.welcome.title == "Ready")

        // Supported browsers include Arc, Dia, Helium, Chrome, Safari, Fresh
        let browsers = OnboardingBrowser.allBrowsers
        #expect(browsers.contains { $0.id == "arc" })
        #expect(browsers.contains { $0.id == "dia" })
        #expect(browsers.contains { $0.id == "helium" })
        #expect(browsers.contains { $0.id == "chrome" })
        #expect(browsers.contains { $0.id == "safari" })
        #expect(browsers.contains { $0.isFreshStart })
    }
}
