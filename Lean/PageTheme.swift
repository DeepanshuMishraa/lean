import AppKit
import SwiftUI

/// Semantic tokens consumed by the page interpreter. The site's role graph
/// stays independent of the chosen palette, so a live switch can reuse it.
struct PageTheme: Equatable, Encodable {
    let isDark: Bool
    let background: String
    let surface: String
    let raised: String
    let text: String
    let textMuted: String
    let border: String
    let accent: String
    let danger: String
    let success: String
    let warning: String
    let info: String

    init?(colors: ThemeColors, semantic: PageSemanticColors) {
        guard let background = Self.hex(colors.windowBackground),
            let surface = Self.hex(colors.palette?.surface ?? colors.activeTabBackground),
            let raised = Self.hex(colors.palette?.raised ?? colors.settingsSidebarBackground),
            let text = Self.hex(colors.primaryText),
            let muted = Self.hex(colors.secondaryText, over: colors.windowBackground),
            let border = Self.hex(colors.omnibarBorder, over: colors.windowBackground),
            let accent = Self.hex(colors.accent ?? Color.accentColor)
        else { return nil }
        self.isDark = colors.isDark
        self.background = background
        self.surface = Self.separated(surface, from: background, minimum: 1.15)
        self.raised = Self.separated(raised, from: background, minimum: 1.05)
        self.text = text
        self.textMuted = muted
        self.border = Self.separated(border, from: background, minimum: 1.5)
        self.accent = accent
        self.danger = semantic.danger
        self.success = semantic.success
        self.warning = semantic.warning
        self.info = semantic.info
    }

    static func channels(_ hex: String) -> [Double]? {
        guard hex.count == 7, hex.first == "#", let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        return [Double(value >> 16 & 255), Double(value >> 8 & 255), Double(value & 255)]
    }

    private static func luminance(_ rgb: [Double]) -> Double {
        let linear = rgb.map { channel -> Double in
            let v = channel / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }

    static func contrast(_ a: [Double], _ b: [Double]) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Cards and hairlines that sit almost on the page colour vanish on the page. Moves `hex`
    /// away from `background` along its own hue until it is `minimum`:1 apart; palettes that
    /// already clear the bar are returned unchanged.
    static func separated(_ hex: String, from background: String, minimum: Double) -> String {
        guard let color = channels(hex), let base = channels(background), contrast(color, base) < minimum else { return hex }
        let black = [0.0, 0, 0], white = [255.0, 255, 255]
        let pole = contrast(black, base) > contrast(white, base) ? black : white
        func mixed(_ t: Double) -> [Double] { zip(color, pole).map { $0 + ($1 - $0) * t } }
        var low = 0.0, high = 1.0
        for _ in 0..<12 {
            let mid = (low + high) / 2
            if contrast(mixed(mid), base) >= minimum { high = mid } else { low = mid }
        }
        let result = mixed(high).map { Int(pole[0] == 0 ? $0.rounded(.down) : $0.rounded(.up)) }
        return String(format: "#%02x%02x%02x", result[0], result[1], result[2])
    }

    private static func hex(_ color: Color, over background: Color? = nil) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let base = background.flatMap { NSColor($0).usingColorSpace(.sRGB) }
        func byte(_ value: CGFloat, _ behind: CGFloat?) -> Int {
            let composited = behind.map { value * rgb.alphaComponent + $0 * (1 - rgb.alphaComponent) } ?? value
            return max(0, min(255, Int((composited * 255).rounded())))
        }
        return String(
            format: "#%02x%02x%02x", byte(rgb.redComponent, base?.redComponent),
            byte(rgb.greenComponent, base?.greenComponent), byte(rgb.blueComponent, base?.blueComponent))
    }
}

struct PageSemanticColors {
    let danger: String
    let success: String
    let warning: String
    let info: String

    init(_ danger: String, _ success: String, _ warning: String, _ info: String) {
        self.danger = danger
        self.success = success
        self.warning = warning
        self.info = info
    }
}

extension BrowserTheme {
    /// Semantic hues from each theme's palette; text contrast is checked by the interpreter.
    func pageSemanticColors(isDark: Bool) -> PageSemanticColors {
        switch self {
        case .catppuccin:
            return isDark
                ? PageSemanticColors("#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa")
                : PageSemanticColors("#d20f39", "#40a02b", "#df8e1d", "#1e66f5")
        case .tokyoNight:
            return isDark
                ? PageSemanticColors("#f7768e", "#9ece6a", "#e0af68", "#7aa2f7")
                : PageSemanticColors("#f52a65", "#587539", "#8c6c3e", "#2e7de9")
        case .dracula:
            return isDark
                ? PageSemanticColors("#ff5555", "#50fa7b", "#f1fa8c", "#8be9fd")
                : PageSemanticColors("#cb3a2a", "#14710a", "#846e15", "#036a96")
        case .one:
            return isDark
                ? PageSemanticColors("#e06c75", "#98c379", "#e5c07b", "#61afef")
                : PageSemanticColors("#e45649", "#50a14f", "#986801", "#4078f2")
        case .nord:
            return PageSemanticColors("#bf616a", "#a3be8c", "#ebcb8b", "#5e81ac")
        case .gruvbox:
            return isDark
                ? PageSemanticColors("#fb4934", "#b8bb26", "#fabd2f", "#83a598")
                : PageSemanticColors("#9d0006", "#79740e", "#b57614", "#076678")
        case .rosePine:
            return isDark
                ? PageSemanticColors("#eb6f92", "#9ccfd8", "#f6c177", "#31748f")
                : PageSemanticColors("#b4637a", "#56949f", "#ea9d34", "#286983")
        case .solarized:
            return PageSemanticColors("#dc322f", "#859900", "#b58900", "#268bd2")
        case .github, .standard:
            return isDark
                ? PageSemanticColors("#f85149", "#3fb950", "#d29922", "#58a6ff")
                : PageSemanticColors("#cf222e", "#1a7f37", "#9a6700", "#0969da")
        }
    }
}

extension PageScripts {
    /// Posted by every subframe from Lean's own world (see page-theme.js); keep the two names in step.
    static let themeFrameMessageName = "leanThemeFrame"

    private static let pageInterpreter: String? = {
        guard let url = Bundle.main.url(forResource: "page-theme", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    /// Installed even when disabled so already-loaded subframes can be toggled.
    static func pageThemeSource(_ theme: PageTheme?) -> String? {
        guard let pageInterpreter, let update = pageThemeUpdate(theme) else { return nil }
        return pageInterpreter + "\n" + update
    }

    static func pageThemeUpdate(_ theme: PageTheme?) -> String? {
        let json: String
        if let theme {
            guard let data = try? JSONEncoder().encode(theme), let encoded = String(data: data, encoding: .utf8) else { return nil }
            json = encoded
        } else {
            json = "null"
        }
        return "globalThis.LeanPageTheme?.apply(\(json));"
    }
}
