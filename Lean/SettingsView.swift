import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: LeanStore

    @State private var historyCleared = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Preferences")
                    .font(store.leanUIFont.font(size: 17, weight: .semibold))
                    .foregroundColor(primaryText)
                Text("Lean appearance and behavior")
                    .font(store.leanUIFont.font(size: 12))
                    .foregroundColor(secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 20)

            // Content Scroll
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // SECTION 1: APPEARANCE
                    SettingsSection(title: "Appearance", uiFont: store.leanUIFont) {
                        CustomSegmentedPicker(
                            options: [
                                SegmentOption(id: AppTheme.light.rawValue, label: "Light", icon: "sun.max.fill"),
                                SegmentOption(id: AppTheme.dark.rawValue, label: "Dark", icon: "moon.fill"),
                                SegmentOption(id: AppTheme.system.rawValue, label: "Auto", icon: "circle.lefthalf.filled")
                            ],
                            selectedId: store.theme.rawValue,
                            isDark: store.isDarkMode,
                            uiFont: store.leanUIFont
                        ) { newId in
                            if let theme = AppTheme(rawValue: newId) {
                                store.theme = theme
                            }
                        }
                    }

                    SettingsSection(title: "Fonts", uiFont: store.leanUIFont) {
                        VStack(spacing: 0) {
                            FontPickerRow(
                                title: "Lean UI",
                                selection: $store.leanUIFont,
                                uiFont: store.leanUIFont,
                                isDark: store.isDarkMode
                            )
                            customDivider
                            FontPickerRow(
                                title: "Web pages",
                                selection: $store.webPageFont,
                                uiFont: store.leanUIFont,
                                isDark: store.isDarkMode
                            )
                        }
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(cardBorder)
                    }

                    // SECTION 2: TABS
                    SettingsSection(title: "Tab Management", uiFont: store.leanUIFont) {
                        VStack(spacing: 12) {
                            // Custom Tab Style Switcher
                            CustomSegmentedPicker(
                                options: [
                                    SegmentOption(id: TabDisplayMode.textOnly.rawValue, label: "Text Only", icon: "text.alignleft"),
                                    SegmentOption(id: TabDisplayMode.iconOnly.rawValue, label: "Icon Only", icon: "square.grid.2x2"),
                                    SegmentOption(id: TabDisplayMode.hybrid.rawValue, label: "Hybrid", icon: "rectangle.badge.checkmark")
                                ],
                                selectedId: store.tabDisplayMode.rawValue,
                                isDark: store.isDarkMode,
                                uiFont: store.leanUIFont
                            ) { newId in
                                if let mode = TabDisplayMode(rawValue: newId) {
                                    store.tabDisplayMode = mode
                                }
                            }

                            // Custom Non-Native Toggles
                            VStack(spacing: 0) {
                                CustomToggleRow(
                                    title: "Show full title on active tab",
                                    subtitle: "Expands page title on active tab, condenses inactive ones",
                                    isOn: $store.showFullTitleOnActiveTab,
                                    isDark: store.isDarkMode,
                                    uiFont: store.leanUIFont
                                )

                                customDivider

                                CustomToggleRow(
                                    title: "Tab switcher previews",
                                    subtitle: "Render visual webpage snapshot thumbnails during ⌃Tab",
                                    isOn: $store.enableThumbnailsInTabSwitcher,
                                    isDark: store.isDarkMode,
                                    uiFont: store.leanUIFont
                                )
                            }
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(cardBorder)
                        }
                    }

                    // SECTION 3: BROWSING & SCROLLING
                    SettingsSection(title: "Browsing Experience", uiFont: store.leanUIFont) {
                        VStack(spacing: 12) {
                            // Custom Scrollbar Style Switcher
                            CustomSegmentedPicker(
                                options: [
                                    SegmentOption(id: ScrollbarStyle.hidden.rawValue, label: "Hidden", icon: "eye.slash"),
                                    SegmentOption(id: ScrollbarStyle.thin.rawValue, label: "Thin", icon: "line.3.horizontal"),
                                    SegmentOption(id: ScrollbarStyle.normal.rawValue, label: "Default", icon: "slider.vertical.3")
                                ],
                                selectedId: store.scrollbarStyle.rawValue,
                                isDark: store.isDarkMode,
                                uiFont: store.leanUIFont
                            ) { newId in
                                if let style = ScrollbarStyle(rawValue: newId) {
                                    store.scrollbarStyle = style
                                }
                            }

                            VStack(spacing: 0) {
                                CustomToggleRow(
                                    title: "Smooth scrolling",
                                    subtitle: "Native WebKit scrolling with smooth in-page navigation",
                                    isOn: $store.smoothScrollingEnabled,
                                    isDark: store.isDarkMode,
                                    uiFont: store.leanUIFont
                                )
                            }
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(cardBorder)
                        }
                    }

                    // SECTION 4: PRIVACY & SYSTEM
                    SettingsSection(title: "Privacy & Engine", uiFont: store.leanUIFont) {
                        VStack(spacing: 0) {
                            // Default Search Engine
                            HStack(spacing: 14) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(secondaryText)
                                    .frame(width: 20)

                                Text("Search Engine")
                                    .font(store.leanUIFont.font(size: 13, weight: .medium))
                                    .foregroundColor(primaryText)

                                Spacer()

                                Text("Google Search")
                                    .font(store.leanUIFont.font(size: 12, weight: .medium))
                                    .foregroundColor(secondaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 48)

                            customDivider

                            // Ad & Tracker Blocker
                            HStack(spacing: 14) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(secondaryText)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Content Blocker")
                                        .font(store.leanUIFont.font(size: 13, weight: .medium))
                                        .foregroundColor(primaryText)
                                    Text("WebKit native tracker and ad filtering")
                                        .font(store.leanUIFont.font(size: 11))
                                        .foregroundColor(secondaryText)
                                }

                                Spacer()

                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(red: 48/255, green: 209/255, blue: 88/255))
                                        .frame(width: 6, height: 6)
                                    Text("Enabled")
                                        .font(store.leanUIFont.font(size: 11.5, weight: .semibold))
                                        .foregroundColor(Color(red: 48/255, green: 209/255, blue: 88/255))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Color(red: 48/255, green: 209/255, blue: 88/255).opacity(0.12),
                                    in: Capsule()
                                )
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)

                            customDivider

                            // Clear History
                            HStack(spacing: 14) {
                                Image(systemName: "trash")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(secondaryText)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Browsing History")
                                        .font(store.leanUIFont.font(size: 13, weight: .medium))
                                        .foregroundColor(primaryText)
                                    Text("Purge session history and omnibar match cache")
                                        .font(store.leanUIFont.font(size: 11))
                                        .foregroundColor(secondaryText)
                                }

                                Spacer()

                                if historyCleared {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("Cleared")
                                            .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                                    }
                                    .foregroundColor(Color(red: 48/255, green: 209/255, blue: 88/255))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .transition(.opacity)
                                } else {
                                    Button(action: {
                                        store.clearHistory()
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                            historyCleared = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                historyCleared = false
                                            }
                                        }
                                    }) {
                                        Text("Clear Cache")
                                            .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 5)
                                            .background(
                                                store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(cardBorder)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(width: 580, height: 600)
        .background(windowBackground)
        .preferredColorScheme(store.colorScheme)
    }

    // MARK: - Color Tokens
    private var primaryText: Color {
        store.isDarkMode ? Color(white: 0.96) : Color(white: 0.12)
    }

    private var secondaryText: Color {
        store.isDarkMode ? Color(white: 0.48) : Color(white: 0.50)
    }

    private var windowBackground: Color {
        store.isDarkMode ? Color(red: 18/255, green: 18/255, blue: 20/255) : Color(red: 247/255, green: 247/255, blue: 249/255)
    }

    private var cardBackground: Color {
        store.isDarkMode ? Color(red: 26/255, green: 26/255, blue: 29/255) : Color.white
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                store.isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.06),
                lineWidth: 1
            )
    }

    private var customDivider: some View {
        Divider()
            .background(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
            .padding(.leading, 16)
    }
}
