import AppKit
import SwiftUI

// The top strip's ground, tinted with the active tab's declared theme
// colour when the setting is on and the page has one. A tint, not the
// full colour: it keeps the strip inside the browser's own theme (a dark
// page never turns the strip dark under a light browser) so every ink
// already on the row stays legible. Ported from Search's ThemedStrip
// (PR #168), which reads only what the page itself declares with
// `theme-color`: no sampling, no guessing. The sidebar layout is
// unaffected.
//
// Its own view, watching the active tab directly, so it is the one thing in
// the row that redraws when a page's colour changes underneath an unchanged
// tab (an SPA repainting its header, say); nothing else here has to know.
struct ThemeColorStrip: ViewModifier {
    @ObservedObject var tab: LeanTab
    let enabled: Bool
    /// The strip's untinted ground, for mixing under the theme colour.
    let window: Color

    private var color: Color? {
        guard enabled,
              let themeColor = tab.themeColor,
              let windowNS = Self.resolved(window),
              let themeNS = themeColor.usingColorSpace(.sRGB) else { return nil }
        return Color(nsColor: Self.tintedStripColor(theme: themeNS, window: windowNS))
    }

    /// Theme colour mixed over the window ground. `amount` is how much of
    /// the page shows through: 0 is the plain browser, 1 the full colour.
    /// Pure so the mix is unit-testable.
    static func tintedStripColor(theme: NSColor, window: NSColor, amount: Double = 0.25) -> NSColor {
        let clamped = min(max(amount, 0), 1)
        let t = theme.usingColorSpace(.sRGB) ?? theme
        let w = window.usingColorSpace(.sRGB) ?? window
        func mix(_ ground: CGFloat, _ tint: CGFloat) -> CGFloat {
            ground * (1 - clamped) + tint * clamped
        }
        return NSColor(
            srgbRed: mix(w.redComponent, t.redComponent),
            green: mix(w.greenComponent, t.greenComponent),
            blue: mix(w.blueComponent, t.blueComponent),
            alpha: 1
        )
    }

    private static func resolved(_ color: Color) -> NSColor? {
        let nsColor = NSColor(color)
        return nsColor.usingColorSpace(.sRGB) ?? nsColor
    }

    func body(content: Content) -> some View {
        Group {
            if let color {
                content.background(color)
            } else {
                // No theming: draw the row exactly as it always looked.
                content
            }
        }
        .animation(.easeInOut(duration: 0.25), value: color)
    }
}
