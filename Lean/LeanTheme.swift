import AppKit
import SwiftUI

enum LeanFont: String, CaseIterable, Identifiable {
    case system = "System"
    case avenirNext = "Avenir Next"
    case helveticaNeue = "Helvetica Neue"
    case jetBrainsMono = "JetBrains Mono"
    case geistMono = "Geist Mono"
    case splineSansMono = "Spline Sans Mono"

    var id: String { rawValue }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard self != .system else {
            return .system(size: size, weight: weight)
        }
        return .custom(rawValue, size: size).weight(weight)
    }

    var cssFamily: String {
        switch self {
        case .system: return "-apple-system, BlinkMacSystemFont, sans-serif"
        default: return "'\(rawValue)', -apple-system, BlinkMacSystemFont, sans-serif"
        }
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
