import SwiftUI

struct TabSwitcherView: View {
    @ObservedObject var store: LeanStore

    var body: some View {
        ZStack {
            // Completely transparent hit-test backdrop so clicking outside closes it without dimming the window
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    store.cancelTabSwitcher()
                }

            Group {
                if store.enableThumbnailsInTabSwitcher {
                    thumbnailCardList
                        .padding(10)
                } else {
                    normalTabList
                        .padding(8)
                }
            }
            .background(
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: store.enableThumbnailsInTabSwitcher ? 18 : 14, style: .continuous))
            )
            .background(
                (store.isDarkMode ? Color.black.opacity(0.80) : Color(white: 0.96).opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: store.enableThumbnailsInTabSwitcher ? 18 : 14, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: store.enableThumbnailsInTabSwitcher ? 18 : 14, style: .continuous)
                    .stroke(
                        store.isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)
            .fixedSize()
            .animation(.spring(response: 0.14, dampingFraction: 0.9), value: store.switcherSelectedIndex)
        }
    }

    // MARK: - Normal Tab Switcher List (Super-fast, minimal)
    private var normalTabList: some View {
        let tabs = store.switcherTabs
        return HStack(spacing: 6) {
            ForEach(0..<tabs.count, id: \.self) { index in
                let tab = tabs[index]
                NormalTabItem(
                    tab: tab,
                    isSelected: index == store.switcherSelectedIndex,
                    isDark: store.isDarkMode,
                    uiFont: store.tabTitleTypeface,
                    headingWeight: store.uiHeadingWeight
                )
                .onTapGesture {
                    store.switcherSelectedIndex = index
                    store.commitTabSwitcher()
                }
            }
        }
    }

    // MARK: - Thumbnail Card List (Rich visual previews)
    private var thumbnailCardList: some View {
        let tabs = store.switcherTabs
        return HStack(spacing: 10) {
            ForEach(0..<tabs.count, id: \.self) { index in
                let tab = tabs[index]
                TabThumbnailCard(
                    tab: tab,
                    isSelected: index == store.switcherSelectedIndex,
                    isDark: store.isDarkMode,
                    uiFont: store.tabTitleTypeface,
                    headingWeight: store.uiHeadingWeight
                )
                .onTapGesture {
                    store.switcherSelectedIndex = index
                    store.commitTabSwitcher()
                }
            }
        }
    }
}

// MARK: - Normal Tab Switcher Item
struct NormalTabItem: View {
    @ObservedObject var tab: LeanTab
    let isSelected: Bool
    let isDark: Bool
    let uiFont: LeanFont
    var headingWeight: LeanFontWeight = .medium

    var body: some View {
        HStack(spacing: 8) {
            TabFaviconView(tab: tab, isDark: isDark, size: 16)

            Text(tab.displayTitle(isSelected: true))
                .font(uiFont.font(size: 13, weight: headingWeight.fontWeight))
                .foregroundColor(
                    isSelected
                        ? (isDark ? .white : .black)
                        : (isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                )
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            isSelected
                ? (isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10))
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected
                        ? (isDark ? Color.white.opacity(0.24) : Color.black.opacity(0.14))
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .scaleEffect(isSelected ? 1.0 : 0.98)
        .animation(.spring(response: 0.14, dampingFraction: 0.9), value: isSelected)
    }
}

// Native macOS VisualEffectBlur for authentic Liquid Glass effect
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Thumbnail Card
struct TabThumbnailCard: View {
    @ObservedObject var tab: LeanTab
    let isSelected: Bool
    let isDark: Bool
    let uiFont: LeanFont
    var headingWeight: LeanFontWeight = .medium

    var body: some View {
        VStack(spacing: 0) {
            // Top Preview Thumbnail
            thumbnailPreview
                .frame(width: 196, height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(6)

            // Bottom Title & Favicon Bar
            HStack(spacing: 8) {
                TabFaviconView(tab: tab, isDark: isDark, size: 16)

                Text(tab.displayTitle(isSelected: true))
                    .font(uiFont.font(size: 13, weight: headingWeight.fontWeight))
                    .foregroundColor(isDark ? .white : .black)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .padding(.bottom, 4)
        }
        .frame(width: 208, height: 160)
        .background(
            cardBackground,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardBorder, lineWidth: isSelected ? 1.5 : 1)
        )
        .scaleEffect(isSelected ? 1.0 : 0.98)
        .animation(.spring(response: 0.14, dampingFraction: 0.9), value: isSelected)
    }

    @ViewBuilder
    private var thumbnailPreview: some View {
        ZStack {
            isDark ? Color(white: 0.12) : Color(white: 0.92)

            if tab.isSettingsPage {
                VStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
                    Text("Settings")
                        .font(uiFont.font(size: 13, weight: headingWeight.fontWeight))
                        .foregroundStyle(isDark ? Color.white.opacity(0.75) : Color.black.opacity(0.70))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = tab.snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 196, height: 118)
                    .clipped()
            } else if tab.url == nil {
                // Clean New Tab Preview
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                            .frame(width: 90, height: 14)
                        Spacer()
                    }
                    Spacer()
                }
            } else {
                // Loading or placeholder
                Ph.browser.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(isDark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
            }
        }
    }

    private var cardBackground: Color {
        if isSelected {
            return isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    private var cardBorder: Color {
        if isSelected {
            return isDark ? Color.white.opacity(0.40) : Color.black.opacity(0.24)
        } else {
            return Color.clear
        }
    }
}
