import AppKit
import SwiftUI

struct LeanFont: RawRepresentable, Hashable, Identifiable, CaseIterable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }

    var id: String { rawValue }
    var description: String { displayName }

    static let geistSans = LeanFont(rawValue: "Geist")
    static let system = LeanFont(rawValue: "System")
    static let geistMono = LeanFont(rawValue: "Geist Mono")
    static let avenirNext = LeanFont(rawValue: "Avenir Next")
    static let helveticaNeue = LeanFont(rawValue: "Helvetica Neue")
    static let jetBrainsMono = LeanFont(rawValue: "JetBrains Mono")
    static let splineSansMono = LeanFont(rawValue: "Spline Sans Mono")

    static var allCases: [LeanFont] {
        [.geistSans, .system, .geistMono, .avenirNext, .helveticaNeue, .jetBrainsMono, .splineSansMono]
    }

    var displayName: String {
        if self == .geistSans { return "Geist Sans" }
        return rawValue
    }

    static func appKitWeight(for weight: Font.Weight) -> Int {
        switch weight {
        case .ultraLight: return 2
        case .thin: return 3
        case .light: return 4
        case .regular: return 5
        case .medium: return 6
        case .semibold: return 8
        case .bold: return 9
        case .heavy: return 10
        case .black: return 11
        default: return 5
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if self == .system {
            return .system(size: size, weight: weight)
        }
        let familyName: String = {
            if self == .geistSans { return "Geist" }
            if self == .geistMono { return "Geist Mono" }
            return rawValue
        }()
        let weightInt = Self.appKitWeight(for: weight)
        if let matched = NSFontManager.shared.font(withFamily: familyName, traits: [], weight: weightInt, size: size) {
            return Font(matched)
        }
        if let base = NSFontManager.shared.font(withFamily: familyName, traits: [], weight: 5, size: size) {
            return Font(base)
        }
        return .custom(familyName, size: size).weight(weight)
    }

    func font(size: CGFloat, fontWeight: LeanFontWeight) -> Font {
        if self == .system {
            return .system(size: size, weight: fontWeight.fontWeight)
        }
        let familyName: String = {
            if self == .geistSans { return "Geist" }
            if self == .geistMono { return "Geist Mono" }
            return rawValue
        }()
        let weightInt = fontWeight.appKitWeight
        if let matched = NSFontManager.shared.font(withFamily: familyName, traits: [], weight: weightInt, size: size) {
            return Font(matched)
        }
        if let base = NSFontManager.shared.font(withFamily: familyName, traits: [], weight: 5, size: size) {
            return Font(base)
        }
        return .custom(familyName, size: size).weight(fontWeight.fontWeight)
    }

    var cssFamily: String {
        if self == .geistSans { return "'Geist', 'Geist Sans', -apple-system, BlinkMacSystemFont, sans-serif" }
        if self == .system { return "-apple-system, BlinkMacSystemFont, sans-serif" }
        // Family names come from the system font list, not a closed set:
        // escape backslashes and quotes before quoting for CSS.
        let family = rawValue
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(family)', -apple-system, BlinkMacSystemFont, sans-serif"
    }
}

enum LeanFontWeight: Int, CaseIterable, Identifiable, Comparable, Codable {
    case ultraLight = 100
    case thin = 200
    case light = 300
    case regular = 400
    case medium = 500
    case semibold = 600
    case bold = 700
    case heavy = 800
    case black = 900

    var id: Int { rawValue }

    static func < (lhs: LeanFontWeight, rhs: LeanFontWeight) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var name: String {
        switch self {
        case .ultraLight: return "Ultralight"
        case .thin: return "Thin"
        case .light: return "Light"
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        case .heavy: return "Heavy"
        case .black: return "Black"
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }

    var nsFontWeight: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }

    var appKitWeight: Int {
        switch self {
        case .ultraLight: return 2
        case .thin: return 3
        case .light: return 4
        case .regular: return 5
        case .medium: return 6
        case .semibold: return 8
        case .bold: return 9
        case .heavy: return 10
        case .black: return 11
        }
    }

    init(closestTo value: Double) {
        let all = Self.allCases
        self = all.min(by: { abs(Double($0.rawValue) - value) < abs(Double($1.rawValue) - value) }) ?? .regular
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    var id: String { rawValue }
}

enum ScrollbarStyle: String, CaseIterable, Identifiable {
    case hidden = "No Scrollbar"
    case thin = "Thin Scrollbar"
    case normal = "Normal"

    var id: String { rawValue }
}

struct ThemeColors {
    let isDark: Bool

    var windowBackground: Color {
        isDark ? Color.black : Color.white
    }

    var topBarBackground: Color {
        isDark ? Color.black : Color.white
    }

    var divider: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    var pinnedButtonBackground: Color {
        isDark ? Color(white: 0.12) : Color(white: 0.94)
    }

    var pinnedButtonHover: Color {
        isDark ? Color(white: 0.20) : Color(white: 0.88)
    }

    var pinnedButtonText: Color {
        isDark ? Color(white: 0.70) : Color(white: 0.52)
    }

    var activeTabBackground: Color {
        isDark ? Color(white: 0.15) : Color(white: 0.93)
    }

    var activeTabText: Color {
        isDark ? Color.white : Color(white: 0.12)
    }

    var inactiveTabText: Color {
        isDark ? Color(white: 0.55) : Color(white: 0.38)
    }

    var inactiveTabHover: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    var omnibarBackground: Color {
        isDark ? Color.black : Color.white
    }

    var omnibarBorder: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var omnibarText: Color {
        isDark ? Color.white : Color.primary
    }

    var omnibarPlaceholder: Color {
        isDark ? Color(white: 0.45) : Color(white: 0.62)
    }

    var omnibarSuggestionSelected: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.04)
    }

    var secondaryText: Color {
        isDark ? Color(white: 0.55) : Color(white: 0.52)
    }
}

extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleanHex.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (44, 45, 50)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }

    func toHex() -> String {
        let nsColor = NSColor(self)
        guard let srgb = nsColor.usingColorSpace(.sRGB) else {
            return "#2C2D32"
        }
        let r = max(0, min(255, Int(round(srgb.redComponent * 255.0))))
        let g = max(0, min(255, Int(round(srgb.greenComponent * 255.0))))
        let b = max(0, min(255, Int(round(srgb.blueComponent * 255.0))))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Standard sRGB perceptual linear luminance (0.0 ... 1.0)
    func relativeLuminance() -> Double {
        let nsColor = NSColor(self)
        guard let srgb = nsColor.usingColorSpace(.sRGB) else {
            return 0.5
        }
        func toLinear(_ c: CGFloat) -> Double {
            let val = Double(max(0, min(1, c)))
            return (val <= 0.04045) ? (val / 12.92) : pow((val + 0.055) / 1.055, 2.4)
        }
        let rLin = toLinear(srgb.redComponent)
        let gLin = toLinear(srgb.greenComponent)
        let bLin = toLinear(srgb.blueComponent)
        return 0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin
    }

    /// Subtle brightness adjustment for gradients and depth
    func adjustBrightness(by amount: CGFloat) -> Color {
        let nsColor = NSColor(self)
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return self }
        let r = max(0, min(1, srgb.redComponent + amount))
        let g = max(0, min(1, srgb.greenComponent + amount))
        let b = max(0, min(1, srgb.blueComponent + amount))
        return Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(srgb.alphaComponent))
    }
}

// MARK: - Adaptive Frame Theme Engine
/// Dynamically derives optimal contrast, translucent glass materials,
/// border strokes, and typography based on the frame's relative luminance and color physics.
struct AdaptiveFrameTheme {
    let isBorderEnabled: Bool
    let frameColor: Color
    let baseThemeColors: ThemeColors
    let isBaseDark: Bool

    let frameLuminance: Double
    let isFrameLight: Bool

    init(isBorderEnabled: Bool, frameColor: Color, baseThemeColors: ThemeColors, isBaseDark: Bool) {
        self.isBorderEnabled = isBorderEnabled
        self.frameColor = frameColor
        self.baseThemeColors = baseThemeColors
        self.isBaseDark = isBaseDark

        if isBorderEnabled {
            let lum = frameColor.relativeLuminance()
            self.frameLuminance = lum
            // Contrast crossover: For L > 0.22, dark foreground has higher contrast (> 5.4:1)
            // than white text. This ensures pastels (lavender, mint, amber, light grey) get
            // crisp ink foreground, while deep tones get luminous white.
            self.isFrameLight = lum > 0.22
        } else {
            self.frameLuminance = isBaseDark ? 0.0 : 1.0
            self.isFrameLight = !isBaseDark
        }
    }

    var effectiveIsDark: Bool {
        isBorderEnabled ? !isFrameLight : isBaseDark
    }

    // MARK: - Foreground Tokens (Text & Icons)

    var primaryText: Color {
        if isBorderEnabled {
            return isFrameLight ? Color(white: 0.08) : Color.white.opacity(0.98)
        }
        return baseThemeColors.activeTabText
    }

    var secondaryText: Color {
        if isBorderEnabled {
            return isFrameLight ? Color(white: 0.10).opacity(0.68) : Color.white.opacity(0.72)
        }
        return baseThemeColors.secondaryText
    }

    var disabledIconText: Color {
        if isBorderEnabled {
            return isFrameLight ? Color(white: 0.10).opacity(0.24) : Color.white.opacity(0.25)
        }
        return baseThemeColors.secondaryText.opacity(0.35)
    }

    var iconHoverBackground: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.black.opacity(0.08) : Color.white.opacity(0.14)
        }
        return isBaseDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    var iconPressedBackground: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.black.opacity(0.15) : Color.white.opacity(0.22)
        }
        return isBaseDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
    }

    // MARK: - Tab Bar Tokens

    var activeTabBackground: Color {
        if isBorderEnabled {
            // Solid card surface, connects seamlessly with the web card (like Arc/Zen in Image 2)
            return isFrameLight ? Color.white : Color(red: 18/255, green: 18/255, blue: 20/255)
        }
        return baseThemeColors.activeTabBackground
    }

    var activeTabStroke: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12)
        }
        return Color.clear
    }

    var activeTabShadow: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.black.opacity(0.06) : Color.black.opacity(0.35)
        }
        return Color.clear
    }

    var activeTabText: Color {
        if isBorderEnabled {
            return isFrameLight ? Color(white: 0.08) : Color.white
        }
        return baseThemeColors.activeTabText
    }

    var inactiveTabBackground: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08)
        }
        return Color.clear
    }

    var inactiveTabText: Color {
        if isBorderEnabled {
            return isFrameLight ? Color(white: 0.12).opacity(0.70) : Color.white.opacity(0.72)
        }
        return baseThemeColors.inactiveTabText
    }

    var inactiveTabHoverBackground: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.black.opacity(0.09) : Color.white.opacity(0.15)
        }
        return baseThemeColors.inactiveTabHover
    }

    var tabCloseButtonForeground: Color {
        if isBorderEnabled {
            return isFrameLight ? Color(white: 0.10).opacity(0.65) : Color.white.opacity(0.72)
        }
        return baseThemeColors.secondaryText
    }

    var tabCloseButtonHoverBackground: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.black.opacity(0.08) : Color.white.opacity(0.14)
        }
        return isBaseDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    // MARK: - Inline URL Bar Tokens

    var inlineURLBarBackground: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.white.opacity(0.92) : Color.white.opacity(0.18)
        }
        return baseThemeColors.activeTabBackground
    }

    var inlineURLBarStroke: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.black.opacity(0.10) : Color.white.opacity(0.20)
        }
        return isBaseDark ? Color.white.opacity(0.15) : Color.black.opacity(0.10)
    }

    var dropdownBackground: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.white : Color(red: 28/255, green: 28/255, blue: 32/255)
        }
        return isBaseDark ? baseThemeColors.omnibarBackground : Color.white
    }

    var dropdownStroke: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.black.opacity(0.09) : Color.white.opacity(0.14)
        }
        return isBaseDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var dropdownShadow: Color {
        if isBorderEnabled {
            return Color.black.opacity(isFrameLight ? 0.12 : 0.40)
        }
        return isBaseDark ? Color.black.opacity(0.35) : Color.black.opacity(0.08)
    }

    // MARK: - Window & Web Card Tokens

    var topSheenGradient: LinearGradient {
        if isBorderEnabled {
            return LinearGradient(
                colors: [
                    frameColor.adjustBrightness(by: isFrameLight ? 0.025 : 0.04),
                    frameColor
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [baseThemeColors.topBarBackground, baseThemeColors.topBarBackground],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var cardCornerRadius: CGFloat {
        isBorderEnabled ? 10.0 : 0.0
    }

    var webCardStroke: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.black.opacity(0.09) : Color.white.opacity(0.14)
        }
        return Color.clear
    }

    var webCardShadow: Color {
        if isBorderEnabled {
            return Color.black.opacity(isFrameLight ? 0.08 : 0.32)
        }
        return Color.clear
    }

    var webCardShadowRadius: CGFloat {
        if isBorderEnabled {
            return isFrameLight ? 8 : 10
        }
        return 0
    }

    var scrollIndicatorColor: Color {
        if isBorderEnabled {
            return isFrameLight ? Color.black.opacity(0.35) : Color.white.opacity(0.40)
        }
        return isBaseDark ? Color.white.opacity(0.45) : Color.black.opacity(0.35)
    }
}

