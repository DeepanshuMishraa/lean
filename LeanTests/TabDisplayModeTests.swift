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
    func dismissInlineURLEditing() {
        let store = LeanStore()
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
    func toolbarCustomizerTests() {
        let store = LeanStore()
        #expect(ToolbarItemType.allCases.count == 7)

        // Reset to default
        store.resetToolbarItems()
        #expect(store.shownToolbarItems.count == 7)
        #expect(store.hiddenToolbarItems.isEmpty)

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
    func inTabSettingsTests() {
        // Address resolution
        #expect(AddressResolver.resolve("settings")?.absoluteString == "lean://settings")
        #expect(AddressResolver.resolve("lean://settings")?.absoluteString == "lean://settings")
        #expect(AddressResolver.resolve("about:settings")?.absoluteString == "lean://settings")

        let store = LeanStore()
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
    func historyManagementTests() {
        let store = LeanStore()
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
}
