import SwiftUI
import Testing
@testable import Lean

struct PageThemeTests {
    @Test("Colours become #rrggbb")
    func hexColours() throws {
        let palette = try #require(BrowserTheme.catppuccin.palette(isDark: true))
        let theme = try #require(PageTheme(background: palette.background, text: palette.text, isDark: true))
        #expect(theme.background == "#1e1e2e")
        #expect(theme.text == "#cdd6f4")
    }

    @Test("The engine gets the theme's colours and mode")
    func sourceCarriesTheme() throws {
        let palette = try #require(BrowserTheme.nord.palette(isDark: true))
        let dark = try #require(PageTheme(background: palette.background, text: palette.text, isDark: true))
        let source = try #require(PageScripts.pageThemeSource(dark))
        #expect(source.contains("darkSchemeBackgroundColor: '#2e3440'"))
        #expect(source.contains("mode: 1"))

        let lightPalette = try #require(BrowserTheme.nord.palette(isDark: false))
        let light = try #require(PageTheme(background: lightPalette.background, text: lightPalette.text, isDark: false))
        #expect(try #require(PageScripts.pageThemeSource(light)).contains("mode: 0"))
    }

    @Test("No theme, no engine")
    func nilThemeNoSource() {
        #expect(PageScripts.pageThemeSource(nil) == nil)
    }
}
