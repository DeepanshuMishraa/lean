import AppKit
import Testing
@testable import Lean

struct ThemeColorStripTests {
    private func gray(_ white: CGFloat) -> NSColor {
        NSColor(srgbRed: white, green: white, blue: white, alpha: 1)
    }

    @Test("Zero tint is the plain browser, full tint the page colour")
    func endpoints() {
        let theme = NSColor(srgbRed: 0.5, green: 0.1, blue: 0.9, alpha: 1)
        let window = gray(1)
        let none = ThemeColorStrip.tintedStripColor(theme: theme, window: window, amount: 0)
        #expect(abs(none.redComponent - 1) < 0.001)
        let full = ThemeColorStrip.tintedStripColor(theme: theme, window: window, amount: 1)
        #expect(abs(full.redComponent - 0.5) < 0.001)
        #expect(abs(full.blueComponent - 0.9) < 0.001)
    }

    @Test("A dark page stays light under a light browser")
    func darkPageLightBrowser() {
        // Telegram violet (#7c3aed) at the default tint over white.
        let violet = NSColor(srgbRed: 0x7c / 255, green: 0x3a / 255, blue: 0xed / 255, alpha: 1)
        let strip = ThemeColorStrip.tintedStripColor(theme: violet, window: gray(1))
        // Still a light ground: dark browser ink stays legible on it.
        #expect(strip.redComponent > 0.8)
        #expect(strip.greenComponent > 0.8)
        #expect(strip.blueComponent > 0.8)
        // …but carrying a hint of the page: blue leads red.
        #expect(strip.blueComponent > strip.redComponent)
    }

    @Test("A light page stays dark under a dark browser")
    func lightPageDarkBrowser() {
        // Figma yellow (#fde047) at the default tint over black.
        let yellow = NSColor(srgbRed: 0xfd / 255, green: 0xe0 / 255, blue: 0x47 / 255, alpha: 1)
        let strip = ThemeColorStrip.tintedStripColor(theme: yellow, window: gray(0))
        #expect(strip.redComponent < 0.3)
        #expect(strip.greenComponent < 0.3)
        #expect(strip.blueComponent < 0.3)
        // …but carrying a hint of the page: red and green lead blue.
        #expect(strip.redComponent > strip.blueComponent)
    }
}
