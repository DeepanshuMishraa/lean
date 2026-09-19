import Foundation
import SwiftUI
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
    func windowBorderPersistence() {
        let store = LeanStore()
        store.enableWindowBorder = true
        #expect(store.enableWindowBorder == true)
        #expect(UserDefaults.standard.bool(forKey: "enableWindowBorder") == true)

        store.windowBorderWidth = 12.0
        #expect(store.windowBorderWidth == 12.0)
        #expect(UserDefaults.standard.double(forKey: "windowBorderWidth") == 12.0)

        // Zen mode persistence and distinctness from window border
        store.enableZenMode = true
        #expect(store.enableZenMode == true)
        #expect(UserDefaults.standard.bool(forKey: "enableZenMode") == true)

        store.enableZenMode = false
        #expect(store.enableZenMode == false)
        #expect(UserDefaults.standard.bool(forKey: "enableZenMode") == false)

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
        #expect(ToolbarItemType.allCases.count == 6)

        // Reset to default
        store.resetToolbarItems()
        #expect(store.shownToolbarItems.count == 6)
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
}
