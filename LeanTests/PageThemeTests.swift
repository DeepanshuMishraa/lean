import SwiftUI
import Testing

@testable import Lean

struct PageThemeTests {
    @Test("Page tokens retain the browser palette's distinct surfaces and semantic hues")
    func semanticTokens() throws {
        let palette = try #require(BrowserTheme.catppuccin.palette(isDark: true))
        let theme = try #require(
            PageTheme(
                colors: ThemeColors(isDark: true, palette: palette),
                semantic: BrowserTheme.catppuccin.pageSemanticColors(isDark: true)))
        #expect(theme.background == "#1e1e2e")
        #expect(theme.surface == "#313244")
        #expect(theme.raised == "#181825")
        #expect(theme.text == "#cdd6f4")
        #expect(theme.textMuted == "#a6adc8")
        #expect(theme.border == "#45475a")
        #expect(theme.accent == "#cba6f7")
        #expect(theme.danger == "#f38ba8")
        #expect(theme.success == "#a6e3a1")
        #expect(theme.warning == "#f9e2af")
        #expect(theme.info == "#89b4fa")
    }

    @Test("Surfaces and borders that sit on the page colour are pushed apart; clear ones are untouched")
    func separation() {
        #expect(PageTheme.separated("#313244", from: "#1e1e2e", minimum: 1.15) == "#313244")
        #expect(PageTheme.separated("#1f1f1f", from: "#000000", minimum: 1.5) != "#1f1f1f")
        #expect(PageTheme.separated("#2c313c", from: "#282c34", minimum: 1.15) != "#2c313c")
    }

    @Test("Every theme variant encodes complete CSS-safe tokens")
    func allVariants() throws {
        for browserTheme in BrowserTheme.allCases {
            for isDark in [false, true] {
                let colors = ThemeColors(isDark: isDark, palette: browserTheme.palette(isDark: isDark))
                let theme = try #require(PageTheme(colors: colors, semantic: browserTheme.pageSemanticColors(isDark: isDark)))
                let data = try JSONEncoder().encode(theme)
                let tokens = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(tokens["isDark"] as? Bool == isDark)
                for key in [
                    "background", "surface", "raised", "text", "textMuted", "border", "accent", "danger", "success", "warning", "info",
                ] {
                    let value = try #require(tokens[key] as? String)
                    #expect(value.range(of: "^#[0-9a-f]{6}$", options: .regularExpression) != nil, "\(browserTheme.name) \(key)")
                }
                let source = try #require(PageScripts.pageThemeSource(theme))
                #expect(source.contains("LeanPageTheme"))
                #expect(!source.contains("DarkReader"))
                #expect(source.contains(theme.background))
                #expect(source.contains(theme.surface))
            }
        }
    }

    @Test("Transparent native tokens are composited rather than losing their opacity")
    func compositedTokens() throws {
        let palette = try #require(BrowserTheme.dracula.palette(isDark: true))
        let theme = try #require(
            PageTheme(
                colors: ThemeColors(isDark: true, palette: palette),
                semantic: BrowserTheme.dracula.pageSemanticColors(isDark: true)))
        #expect(theme.border == "#454e6d")
        #expect(theme.textMuted != theme.text)
    }

    @Test("Disabled pages still get the dormant interpreter so subframes can be enabled live")
    func disabledInterpreter() throws {
        #expect(try #require(PageScripts.pageThemeSource(nil)).contains("LeanPageTheme?.apply(null)"))
        #expect(PageScripts.pageThemeUpdate(nil) == "globalThis.LeanPageTheme?.apply(null);")
    }
}
