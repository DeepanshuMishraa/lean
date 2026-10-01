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
        for (hex, base, minimum) in [("#1f1f1f", "#000000", 1.5), ("#2c313c", "#282c34", 1.15), ("#fffbeb", "#fffbeb", 1.05)] {
            let moved = PageTheme.separated(hex, from: base, minimum: minimum)
            let a = PageTheme.channels(moved), b = PageTheme.channels(base)
            #expect(moved != hex)
            #expect(PageTheme.contrast(a ?? [], b ?? []) >= minimum, "\(hex) on \(base) -> \(moved)")
        }
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
                // The interpreter receives exactly the encoded tokens, decoded from the apply() call.
                let update = try #require(PageScripts.pageThemeUpdate(theme))
                let payload = try #require(update.range(of: "apply(").map { String(update[$0.upperBound...].dropLast(2)) })
                let applied = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
                #expect(applied["background"] as? String == theme.background)
                #expect(applied["surface"] as? String == theme.surface)
                #expect(source.hasSuffix(update))
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
