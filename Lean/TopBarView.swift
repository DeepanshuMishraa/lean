import SwiftUI

struct TopBarView: View {
    @ObservedObject var store: LeanStore
    @State private var isTabStripHovered = false
    @State private var tabScrollMetrics = HorizontalScrollMetrics()
    @State private var tabContentWidth: CGFloat = 0
    @State private var tabViewportWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            // Space reserved for native macOS traffic lights (centered at y = 16, x = 9..69)
            Spacer()
                .frame(width: 80)

            // Horizontal Tabs (New Tab or user opened tabs only - no default pinned sites!)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.tabs) { tab in
                        TopBarTabItem(
                            tab: tab,
                            isSelected: tab.id == store.selectedID,
                            store: store,
                            onSelect: {
                                if tab.id == store.selectedID && tab.url != nil {
                                    if store.isFloatingOmnibarVisible {
                                        store.dismissFloatingOmnibar()
                                    } else {
                                        store.showFloatingOmnibar(mode: .navigate)
                                    }
                                } else {
                                    store.switchToTab(id: tab.id)
                                }
                            },
                            onClose: {
                                store.close(tab)
                            }
                        )
                    }

                    // New Tab "+" Button (opens homepage)
                    InteractiveIconButton(
                        systemImage: "plus",
                        helpText: "New Tab (⌘T)",
                        size: 24,
                        iconSize: 11,
                        color: store.themeColors.secondaryText,
                        isDark: store.isDarkMode
                    ) {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                            store.newTab()
                        }
                    }
                }
                .padding(.vertical, 5)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: TabContentWidthKey.self, value: geometry.size.width)
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.tabs.map(\.id))
            }
            .background(HorizontalScrollWheelBridge(metrics: $tabScrollMetrics))
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: TabViewportWidthKey.self, value: geometry.size.width)
                }
            }
            .onPreferenceChange(TabContentWidthKey.self) { tabContentWidth = $0 }
            .onPreferenceChange(TabViewportWidthKey.self) { tabViewportWidth = $0 }
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    if isTabStripHovered && tabContentWidth > tabViewportWidth + 1 {
                        let trackWidth = max(0, geometry.size.width - 8)
                        let thumbWidth = max(24, trackWidth * tabViewportWidth / tabContentWidth)
                        let scrollableWidth = max(1, tabContentWidth - tabViewportWidth)
                        let thumbTravel = max(0, trackWidth - thumbWidth)
                        let thumbOffset = thumbTravel * min(tabScrollMetrics.offset, scrollableWidth) / scrollableWidth
                        Capsule()
                            .fill(store.isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.35))
                            .frame(width: thumbWidth, height: 2)
                            .offset(
                                x: 4 + thumbOffset,
                                y: geometry.size.height - 3
                            )
                    }
                }
                .allowsHitTesting(false)
            }
            .onHover { isTabStripHovered = $0 }

            Spacer()

            // Quick Theme Toggle (Light / Dark Mode)
            InteractiveIconButton(
                systemImage: store.isDarkMode ? "sun.max.fill" : "moon.fill",
                helpText: store.isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode",
                size: 26,
                iconSize: 12,
                color: store.themeColors.secondaryText,
                isDark: store.isDarkMode
            ) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    store.toggleTheme()
                }
            }

            // Settings Button (⌘,)
            InteractiveIconButton(
                systemImage: "gearshape",
                helpText: "Settings (⌘,)",
                size: 26,
                iconSize: 12,
                color: store.themeColors.secondaryText,
                isDark: store.isDarkMode
            ) {
                store.openSettings()
            }

            Spacer().frame(width: 12)
        }
        .frame(height: 36)
        .padding(.bottom, 2)
        .background(store.themeColors.topBarBackground)
        .animation(.easeInOut(duration: 0.2), value: store.isDarkMode)
    }
}

private struct TopBarTabItem: View {
    @ObservedObject var tab: LeanTab
    let isSelected: Bool
    @ObservedObject var store: LeanStore
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        Group {
            switch store.tabDisplayMode {
            case .textOnly:
                textOnlyContent
            case .iconOnly:
                iconOnlyContent
            case .hybrid:
                hybridContent
            }
        }
        .frame(height: 26)
        .background(
            isSelected
                ? store.themeColors.activeTabBackground
                : (isHovered ? store.themeColors.inactiveTabHover : Color.clear),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .help(tab.displayTitle(isSelected: isSelected, showFullTitle: true))
        .onTapGesture {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                onSelect()
            }
        }
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovered
            }
        }
        .contextMenu {
            Button("Close Tab", action: onClose)
            Button("Reload") { tab.reload() }
            if tab.canGoBack {
                Button("Back") { tab.goBack() }
            }
            if tab.canGoForward {
                Button("Forward") { tab.goForward() }
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isSelected)
    }

    // MARK: - Subviews for Modes

    @ViewBuilder
    private var textOnlyContent: some View {
        HStack(spacing: 6) {
            Text(tab.displayTitle(isSelected: isSelected, showFullTitle: store.showFullTitleOnActiveTab))
                .font(store.leanUIFont.font(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(
                    isSelected
                        ? store.themeColors.activeTabText
                        : store.themeColors.inactiveTabText
                )
                .lineLimit(1)

            if isHovered {
                closeButton
            }
        }
        .padding(.horizontal, isSelected ? 14 : 10)
    }

    @ViewBuilder
    private var iconOnlyContent: some View {
        ZStack {
            if isHovered {
                closeButton
            } else {
                TabFaviconView(tab: tab, isDark: store.isDarkMode, size: 14)
                    .transition(.opacity)
            }
        }
        .frame(width: 28, height: 26)
    }

    @ViewBuilder
    private var hybridContent: some View {
        HStack(spacing: 6) {
            TabFaviconView(tab: tab, isDark: store.isDarkMode, size: 14)

            Text(tab.displayTitle(isSelected: isSelected, showFullTitle: store.showFullTitleOnActiveTab))
                .font(store.leanUIFont.font(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(
                    isSelected
                        ? store.themeColors.activeTabText
                        : store.themeColors.inactiveTabText
                )
                .lineLimit(1)

            if isHovered {
                closeButton
            }
        }
        .padding(.horizontal, isSelected ? 12 : 9)
    }

    private var closeButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                onClose()
            }
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(store.themeColors.secondaryText)
                .frame(width: 14, height: 14)
                .background(
                    isHovered ? (store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08)) : Color.clear,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }
}

private struct InteractiveIconButton: View {
    let systemImage: String
    let helpText: String
    let size: CGFloat
    let iconSize: CGFloat
    let color: Color
    let isDark: Bool
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(isHovered ? (isDark ? .white : .black) : color)
                .frame(width: size, height: size)
                .background(
                    (isPressed
                        ? (isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))
                        : (isHovered ? (isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)) : Color.clear)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
                .animation(.spring(response: 0.20, dampingFraction: 0.75), value: isHovered)
                .animation(.spring(response: 0.15, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { isHovered = $0 }
    }
}
