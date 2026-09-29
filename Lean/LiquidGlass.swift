import SwiftUI

/// Liquid Glass surfaces. Glass only reads as glass with something behind it
/// to refract, so the window turns translucent (see WindowConfigurator) and
/// the chrome floats over it: rounded page card, glass tab groups, glass
/// popovers. Every helper falls back to the plain look when glass is off.
extension LeanStore {
    /// The setting, gated on the OS that has the material.
    var glassActive: Bool {
        if #available(macOS 26, *) { return liquidGlassEnabled }
        return false
    }
}

extension View {
    /// A group of toolbar controls on one glass capsule.
    @ViewBuilder
    func leanGlassGroup(_ active: Bool) -> some View {
        if active, #available(macOS 26, *) {
            padding(.horizontal, 3).glassEffect(.regular, in: .capsule)
        } else {
            self
        }
    }

    /// Glass in a rounded rectangle when active; otherwise untouched.
    @ViewBuilder
    func leanGlassIf(_ active: Bool, radius: CGFloat, interactive: Bool = false) -> some View {
        if active, #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: radius))
        } else {
            self
        }
    }

    /// The drop shadow under a page or sidebar card. Skipped in glass mode:
    /// a large blurred shadow behind a full-window card (with a live web view
    /// inside) is re-rendered off-screen on every frame, and the glass window
    /// already separates the card from the background.
    @ViewBuilder
    func leanCardShadow(glass: Bool, color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        if glass {
            self
        } else {
            shadow(color: color, radius: radius, x: x, y: y)
        }
    }

    /// The surface of a floating panel: glass, or the opaque card with a
    /// blur, hairline and shadow it has always had.
    func leanPopoverSurface(glass: Bool, isDark: Bool, stroke: Color, fill: Color? = nil, radius: CGFloat = 11) -> some View {
        modifier(LeanPopoverSurface(glass: glass, isDark: isDark, stroke: stroke, fill: fill, radius: radius))
    }
}

struct LeanPopoverSurface: ViewModifier {
    let glass: Bool
    let isDark: Bool
    let stroke: Color
    let fill: Color?
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if glass, #available(macOS 26, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: radius + 4))
                .shadow(color: Color.black.opacity(isDark ? 0.32 : 0.12), radius: 22, x: 0, y: 8)
        } else {
            content
                .background(
                    fill ?? (isDark ? Color(red: 18 / 255, green: 18 / 255, blue: 21 / 255) : Color(white: 0.995)).opacity(0.97)
                )
                .background(VisualEffectBlur(material: .popover, blendingMode: .withinWindow))
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(stroke, lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.12), radius: 18, x: 0, y: 8)
                .shadow(color: Color.black.opacity(isDark ? 0.20 : 0.04), radius: 2, x: 0, y: 1)
        }
    }
}
