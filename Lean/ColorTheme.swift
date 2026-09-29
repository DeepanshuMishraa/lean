import SwiftUI

/// The colours a colour theme supplies for one mode. Everything the chrome
/// needs is derived from these seven.
struct ThemePalette: Equatable {
    /// Window and page chrome.
    let background: Color
    /// Active tab, cards, grouped rows.
    let surface: Color
    /// Popovers and dropdowns.
    let raised: Color
    let border: Color
    let text: Color
    let textMuted: Color
    let accent: Color

    fileprivate init(_ background: String, _ surface: String, _ raised: String, _ border: String,
                     _ text: String, _ muted: String, _ accent: String,
                     borderOpacity: Double = 1, mutedOpacity: Double = 1) {
        self.background = Color(hex: background)
        self.surface = Color(hex: surface)
        self.raised = Color(hex: raised)
        self.border = Color(hex: border).opacity(borderOpacity)
        self.text = Color(hex: text)
        self.textMuted = Color(hex: muted).opacity(mutedOpacity)
        self.accent = Color(hex: accent)
    }
}

/// A named colour theme with a dark and a light variant. The interface
/// theme (Light / Dark / System) picks which variant is on screen.
enum BrowserTheme: String, CaseIterable, Identifiable, Codable {
    case standard
    case catppuccin
    case tokyoNight
    case dracula
    case one
    case nord
    case gruvbox
    case rosePine
    case solarized
    case github

    var id: String { rawValue }

    var name: String {
        switch self {
        case .standard: "Default"
        case .catppuccin: "Catppuccin"
        case .tokyoNight: "Tokyo Night"
        case .dracula: "Dracula"
        case .one: "One"
        case .nord: "Nord"
        case .gruvbox: "Gruvbox"
        case .rosePine: "Rosé Pine"
        case .solarized: "Solarized"
        case .github: "GitHub"
        }
    }

    /// The names of the two variants, dark first.
    var variantNames: (dark: String, light: String) {
        switch self {
        case .standard: ("Dark", "Light")
        case .catppuccin: ("Mocha", "Latte")
        case .tokyoNight: ("Night", "Day")
        case .dracula: ("Dracula", "Alucard")
        case .one: ("One Dark", "One Light")
        case .nord: ("Polar Night", "Snow Storm")
        case .gruvbox: ("Dark", "Light")
        case .rosePine: ("Rosé Pine", "Dawn")
        case .solarized: ("Dark", "Light")
        case .github: ("Dark", "Light")
        }
    }

    /// Nil for the default look.
    func palette(isDark: Bool) -> ThemePalette? {
        switch self {
        case .standard:
            return nil
        // Sources: catppuccin/palette (Mocha, Latte).
        case .catppuccin:
            return isDark
                ? ThemePalette("#1e1e2e", "#313244", "#181825", "#45475a", "#cdd6f4", "#a6adc8", "#cba6f7")
                : ThemePalette("#eff1f5", "#ccd0da", "#e6e9ef", "#bcc0cc", "#4c4f69", "#6c6f85", "#8839ef")
        // Sources: folke/tokyonight.nvim (night, day).
        case .tokyoNight:
            return isDark
                ? ThemePalette("#1a1b26", "#292e42", "#16161e", "#3b4261", "#c0caf5", "#a9b1d6", "#7aa2f7")
                : ThemePalette("#e1e2e7", "#c4c8da", "#d0d5e3", "#a8aecb", "#3760bf", "#6172b0", "#2e7de9")
        // Sources: Dracula spec; Alucard is Dracula's official light variant.
        case .dracula:
            return isDark
                ? ThemePalette("#282a36", "#44475a", "#21222c", "#6272a4", "#f8f8f2", "#f8f8f2", "#bd93f9",
                               borderOpacity: 0.5, mutedOpacity: 0.62)
                : ThemePalette("#fffbeb", "#cfcfde", "#fffbeb", "#cfcfde", "#1f1f1f", "#6c664b", "#644ac9")
        // Sources: Atom One Dark / One Light.
        case .one:
            return isDark
                ? ThemePalette("#282c34", "#2c313c", "#21252b", "#3e4451", "#abb2bf", "#9da5b4", "#61afef")
                : ThemePalette("#fafafa", "#eaeaeb", "#f0f0f0", "#dbdbdc", "#383a42", "#696c77", "#4078f2")
        // Sources: nordtheme.com palette (Polar Night dark, Snow Storm light).
        case .nord:
            return isDark
                ? ThemePalette("#2e3440", "#434c5e", "#3b4252", "#4c566a", "#eceff4", "#d8dee9", "#88c0d0",
                               mutedOpacity: 0.72)
                : ThemePalette("#eceff4", "#d8dee9", "#e5e9f0", "#4c566a", "#2e3440", "#4c566a", "#5e81ac",
                               borderOpacity: 0.25)
        // Sources: morhetz/gruvbox.
        case .gruvbox:
            return isDark
                ? ThemePalette("#282828", "#504945", "#3c3836", "#665c54", "#ebdbb2", "#a89984", "#fe8019")
                : ThemePalette("#fbf1c7", "#ebdbb2", "#f2e5bc", "#d5c4a1", "#3c3836", "#7c6f64", "#af3a03")
        // Sources: rosepinetheme.com (main, dawn).
        case .rosePine:
            return isDark
                ? ThemePalette("#191724", "#26233a", "#1f1d2e", "#403d52", "#e0def4", "#908caa", "#c4a7e7")
                : ThemePalette("#faf4ed", "#f2e9e1", "#fffaf3", "#dfdad9", "#575279", "#797593", "#907aa9")
        // Sources: ethanschoonover.com/solarized.
        case .solarized:
            return isDark
                ? ThemePalette("#002b36", "#073642", "#073642", "#586e75", "#93a1a1", "#839496", "#268bd2",
                               borderOpacity: 0.6)
                : ThemePalette("#fdf6e3", "#eee8d5", "#eee8d5", "#93a1a1", "#586e75", "#839496", "#268bd2",
                               borderOpacity: 0.5)
        // Sources: GitHub Primer (dark, light).
        case .github:
            return isDark
                ? ThemePalette("#0d1117", "#21262d", "#161b22", "#30363d", "#e6edf3", "#7d8590", "#2f81f7")
                : ThemePalette("#ffffff", "#eaeef2", "#f6f8fa", "#d0d7de", "#1f2328", "#656d76", "#0969da")
        }
    }
}

// MARK: - Palette in the environment

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue: ThemePalette? = nil
}

extension EnvironmentValues {
    /// The colour theme's palette for the current mode, for views that only
    /// receive `isDark` (settings rows, groups).
    var themePalette: ThemePalette? {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

// MARK: - Picker

/// Theme tiles for Settings: each shows the variant that is on screen now
/// (dark or light), so the choice is previewed exactly as it will look.
struct ColorThemePicker: View {
    @ObservedObject var store: LeanStore

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(BrowserTheme.allCases) { theme in
                tile(for: theme)
            }
        }
    }

    private func tile(for theme: BrowserTheme) -> some View {
        let isDark = store.isDarkMode
        let palette = theme.palette(isDark: isDark)
        let background = palette?.background ?? (isDark ? Color.black : Color.white)
        let surface = palette?.surface ?? (isDark ? Color(white: 0.15) : Color(white: 0.93))
        let text = palette?.text ?? (isDark ? Color(white: 0.94) : Color(white: 0.12))
        let muted = palette?.textMuted ?? (isDark ? Color(white: 0.55) : Color(white: 0.52))
        let accent = palette?.accent ?? (isDark ? Color.white : Color.black)
        let selected = store.colorTheme == theme
        let variant = isDark ? theme.variantNames.dark : theme.variantNames.light

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { store.colorTheme = theme }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // A miniature window: tab, address bar, page lines.
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Capsule().fill(surface).frame(width: 34, height: 7)
                        Capsule().fill(muted.opacity(0.45)).frame(width: 22, height: 7)
                        Spacer(minLength: 0)
                        Circle().fill(accent).frame(width: 7, height: 7)
                    }
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(surface)
                        .frame(height: 12)
                    Capsule().fill(text.opacity(0.85)).frame(width: 70, height: 4)
                    Capsule().fill(muted.opacity(0.7)).frame(width: 96, height: 4)
                }
                .padding(8)
                .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
                )

                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(theme.name)
                            .font(store.headingFont(size: 12))
                            .foregroundColor(store.themeColors.primaryText)
                        Text(variant)
                            .font(store.bodyFont(size: 10.5))
                            .foregroundColor(store.themeColors.secondaryText)
                    }
                    Spacer(minLength: 0)
                    if selected {
                        Circle()
                            .fill(store.themeColors.accent ?? store.themeColors.primaryText)
                            .frame(width: 7, height: 7)
                    }
                }
            }
            .padding(8)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                selected ? store.themeColors.primaryText.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected
                            ? (store.themeColors.accent ?? store.themeColors.primaryText.opacity(0.5))
                            : store.themeColors.primaryText.opacity(0.08),
                        lineWidth: selected ? 1.5 : 0.75
                    )
            )
        }
        .buttonStyle(.hitArea)
        .accessibilityLabel("\(theme.name), \(variant)")
    }
}
