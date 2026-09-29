import SwiftUI
import Testing
@testable import Lean

struct ColorThemeTests {
    @Test("The default theme supplies no palette, so the built-in look is untouched")
    func defaultHasNoPalette() {
        #expect(BrowserTheme.standard.palette(isDark: true) == nil)
        #expect(BrowserTheme.standard.palette(isDark: false) == nil)
    }

    @Test("Every named theme has a dark and a light variant that differ")
    func namedThemesHaveBothVariants() throws {
        for theme in BrowserTheme.allCases where theme != .standard {
            let dark = try #require(theme.palette(isDark: true), "\(theme.name) dark")
            let light = try #require(theme.palette(isDark: false), "\(theme.name) light")
            #expect(dark != light)
            #expect(dark.background.relativeLuminance() < light.background.relativeLuminance(), "\(theme.name)")
        }
    }

    @Test("Variant names follow each theme's own naming")
    func variantNames() {
        #expect(BrowserTheme.catppuccin.variantNames.dark == "Mocha")
        #expect(BrowserTheme.catppuccin.variantNames.light == "Latte")
        #expect(BrowserTheme.dracula.variantNames.light == "Alucard")
    }

    @Test("Catppuccin Mocha uses its published base colour")
    func catppuccinMochaBase() throws {
        let palette = try #require(BrowserTheme.catppuccin.palette(isDark: true))
        #expect(palette.background.toHex() == "#1E1E2E")
        #expect(try #require(BrowserTheme.catppuccin.palette(isDark: false)).background.toHex() == "#EFF1F5")
    }

    @Test("Theme colours fall back to the built-in values without a palette")
    func fallbackWithoutPalette() {
        #expect(ThemeColors(isDark: true).windowBackground.toHex() == "#000000")
        #expect(ThemeColors(isDark: false).windowBackground.toHex() == "#FFFFFF")
    }
}
