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
                HStack(spacing: 5) {
                    ForEach(store.tabs) { tab in
                        TopBarTabItem(
                            tab: tab,
                            isSelected: tab.id == store.selectedID,
                            store: store,
                            onSelect: { handleTabSelection(tab) },
                            onClose: { store.close(tab) }
                        )
                    }

                    if store.isToolbarItemShown(.newTab) {
                        InteractiveIconButton(
                            systemImage: "plus",
                            helpText: "New Tab (⌘T)",
                            size: store.enableWindowBorder ? 26 : 24,
                            iconSize: 11,
                            color: store.adaptiveTheme.secondaryText,
                            hoverColor: store.adaptiveTheme.primaryText,
                            disabledColor: store.adaptiveTheme.disabledIconText,
                            hoverBackground: store.adaptiveTheme.iconHoverBackground,
                            pressedBackground: store.adaptiveTheme.iconPressedBackground,
                            isDark: store.adaptiveTheme.effectiveIsDark
                        ) {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                                store.newTab()
                            }
                        }
                    }
                }
                .padding(.vertical, store.enableWindowBorder ? 3 : 5)
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
                            .fill(store.adaptiveTheme.scrollIndicatorColor)
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

            // Navigation Controls (Back, Forward, Reload) - Hidden on homepage or if not shown
            if store.selectedTab?.url != nil {
                let showBack = store.isToolbarItemShown(.back)
                let showForward = store.isToolbarItemShown(.forward)
                let showReload = store.isToolbarItemShown(.reload)

                if showBack || showForward || showReload {
                    HStack(spacing: 2) {
                        if showBack {
                            InteractiveIconButton(
                                systemImage: "chevron.left",
                                helpText: "Back (⌘[)",
                                size: 24,
                                iconSize: 12,
                                color: store.adaptiveTheme.secondaryText,
                                hoverColor: store.adaptiveTheme.primaryText,
                                disabledColor: store.adaptiveTheme.disabledIconText,
                                hoverBackground: store.adaptiveTheme.iconHoverBackground,
                                pressedBackground: store.adaptiveTheme.iconPressedBackground,
                                isDark: store.adaptiveTheme.effectiveIsDark,
                                isEnabled: store.selectedTab?.canGoBack == true
                            ) {
                                store.selectedTab?.goBack()
                            }
                        }

                        if showForward {
                            InteractiveIconButton(
                                systemImage: "chevron.right",
                                helpText: "Forward (⌘])",
                                size: 24,
                                iconSize: 12,
                                color: store.adaptiveTheme.secondaryText,
                                hoverColor: store.adaptiveTheme.primaryText,
                                disabledColor: store.adaptiveTheme.disabledIconText,
                                hoverBackground: store.adaptiveTheme.iconHoverBackground,
                                pressedBackground: store.adaptiveTheme.iconPressedBackground,
                                isDark: store.adaptiveTheme.effectiveIsDark,
                                isEnabled: store.selectedTab?.canGoForward == true
                            ) {
                                store.selectedTab?.goForward()
                            }
                        }

                        if showReload {
                            InteractiveIconButton(
                                systemImage: "arrow.clockwise",
                                helpText: "Reload (⌘R)",
                                size: 24,
                                iconSize: 12,
                                color: store.adaptiveTheme.secondaryText,
                                hoverColor: store.adaptiveTheme.primaryText,
                                disabledColor: store.adaptiveTheme.disabledIconText,
                                hoverBackground: store.adaptiveTheme.iconHoverBackground,
                                pressedBackground: store.adaptiveTheme.iconPressedBackground,
                                isDark: store.adaptiveTheme.effectiveIsDark,
                                isEnabled: store.selectedTab?.url != nil
                            ) {
                                store.selectedTab?.reload()
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))

                    Spacer().frame(width: 4)
                }
            }

            // Window & Workspace Actions
            let showTheme = store.isToolbarItemShown(.themeToggle)
            let showSettings = store.isToolbarItemShown(.settings)

            if showTheme || showSettings {
                HStack(spacing: 2) {
                    if showTheme {
                        InteractiveIconButton(
                            systemImage: store.isDarkMode ? "sun.max.fill" : "moon.fill",
                            helpText: store.isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode",
                            size: 24,
                            iconSize: 12,
                            color: store.adaptiveTheme.secondaryText,
                            hoverColor: store.adaptiveTheme.primaryText,
                            disabledColor: store.adaptiveTheme.disabledIconText,
                            hoverBackground: store.adaptiveTheme.iconHoverBackground,
                            pressedBackground: store.adaptiveTheme.iconPressedBackground,
                            isDark: store.adaptiveTheme.effectiveIsDark
                        ) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                store.toggleTheme()
                            }
                        }
                    }

                    if showSettings {
                        InteractiveIconButton(
                            systemImage: "gearshape",
                            helpText: "Settings (⌘,)",
                            size: 24,
                            iconSize: 12,
                            color: store.adaptiveTheme.secondaryText,
                            hoverColor: store.adaptiveTheme.primaryText,
                            disabledColor: store.adaptiveTheme.disabledIconText,
                            hoverBackground: store.adaptiveTheme.iconHoverBackground,
                            pressedBackground: store.adaptiveTheme.iconPressedBackground,
                            isDark: store.adaptiveTheme.effectiveIsDark
                        ) {
                            store.openSettings()
                        }
                    }
                }
            }

            Spacer().frame(width: 12)
        }
        .frame(height: store.enableWindowBorder ? 34 : 36)
        .background(
            store.enableWindowBorder
                ? AnyView(Color.clear)
                : AnyView(store.themeColors.topBarBackground)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if store.isInlineURLEditing {
                store.dismissInlineURLEditing()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isDarkMode)
        .animation(.easeInOut(duration: 0.2), value: store.enableWindowBorder)
        .animation(.easeInOut(duration: 0.2), value: store.effectiveZenColor)
    }

    private func handleTabSelection(_ tab: LeanTab) {
        if tab.id == store.selectedID {
            if !store.isInlineURLEditing {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    store.isInlineURLEditing = true
                }
            }
        } else {
            store.switchToTab(id: tab.id)
        }
    }
}

private struct TopBarTabItem: View {
    @ObservedObject var tab: LeanTab
    let isSelected: Bool
    @ObservedObject var store: LeanStore
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    private var showCloseOnHover: Bool {
        isHovered && !(isSelected && store.isInlineURLEditing)
    }

    var body: some View {
        tabContent
            .frame(height: store.enableWindowBorder ? 27 : 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? store.adaptiveTheme.activeTabBackground
                            : (isHovered ? store.adaptiveTheme.inactiveTabHoverBackground : store.adaptiveTheme.inactiveTabBackground)
                    )
                    .overlay(
                        isSelected && store.enableWindowBorder
                            ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(store.adaptiveTheme.activeTabStroke, lineWidth: 1)
                            : nil
                    )
                    .shadow(
                        color: isSelected && store.enableWindowBorder ? store.adaptiveTheme.activeTabShadow : Color.clear,
                        radius: store.adaptiveTheme.isFrameLight ? 2 : 4,
                        x: 0,
                        y: 1
                    )
            )
            .contentShape(Rectangle())
            .help(tab.displayTitle(isSelected: isSelected, showFullTitle: true))
            .onTapGesture {
                if !(isSelected && store.isInlineURLEditing) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        onSelect()
                    }
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
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isSelected && store.isInlineURLEditing)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isSelected)
    }

    @ViewBuilder
    private var tabContent: some View {
        if isSelected && store.isInlineURLEditing {
            InlineURLBar(tab: tab, store: store)
        } else {
            switch store.tabDisplayMode {
            case .textOnly:
                textOnlyContent
            case .iconOnly:
                iconOnlyContent
            case .hybrid:
                hybridContent
            }
        }
    }

    // MARK: - Subviews for Modes

    @ViewBuilder
    private var textOnlyContent: some View {
        HStack(spacing: 6) {
            Text(tab.displayTitle(isSelected: isSelected, showFullTitle: store.showFullTitleOnActiveTab))
                .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                .foregroundColor(
                    isSelected
                        ? store.adaptiveTheme.activeTabText
                        : store.adaptiveTheme.inactiveTabText
                )
                .lineLimit(1)

            if isHovered {
                closeButton
            }
        }
        .padding(.horizontal, isSelected ? 13 : 9)
    }

    @ViewBuilder
    private var iconOnlyContent: some View {
        HStack(spacing: 5) {
            TabFaviconView(tab: tab, isDark: store.adaptiveTheme.effectiveIsDark, size: 14)

            if showCloseOnHover {
                closeButton
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.7)),
                        removal: .opacity
                    ))
            }
        }
        .padding(.horizontal, showCloseOnHover ? 8 : 7)
        .frame(height: 26)
        .frame(minWidth: 28)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isHovered)
    }

    @ViewBuilder
    private var hybridContent: some View {
        HStack(spacing: 6) {
            TabFaviconView(tab: tab, isDark: store.adaptiveTheme.effectiveIsDark, size: 14)

            Text(tab.displayTitle(isSelected: isSelected, showFullTitle: store.showFullTitleOnActiveTab))
                .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                .foregroundColor(
                    isSelected
                        ? store.adaptiveTheme.activeTabText
                        : store.adaptiveTheme.inactiveTabText
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
                .foregroundColor(store.adaptiveTheme.tabCloseButtonForeground)
                .frame(width: 14, height: 14)
                .background(
                    isHovered ? store.adaptiveTheme.tabCloseButtonHoverBackground : Color.clear,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }
}

private struct InlineURLBar: View {
    @ObservedObject var tab: LeanTab
    @ObservedObject var store: LeanStore
    @FocusState private var isFieldFocused: Bool
    @State private var text = ""
    @State private var selectedIndex = 0

    private var openTabsForSuggestions: [(id: UUID, title: String, url: URL)] {
        store.tabs.compactMap { t in
            guard let url = t.url, t.id != tab.id else { return nil }
            return (id: t.id, title: t.title, url: url)
        }
    }

    private var suggestions: [OmnibarSuggestion] {
        guard !text.isEmpty else { return [] }
        return OmnibarService.shared.suggestions(
            for: text,
            history: store.visitedHistory,
            openTabs: openTabsForSuggestions,
            searchEngine: store.searchEngine
        )
    }

    private func suggestionIcon(for match: OmnibarSuggestion) -> String {
        if match.isSearch {
            return "magnifyingglass"
        } else if match.isSwitchToTab {
            return "arrow.right.circle"
        } else {
            return "globe"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            TabFaviconView(tab: tab, isDark: store.adaptiveTheme.effectiveIsDark, size: 13)

            TextField("Search or enter URL...", text: $text)
                .textFieldStyle(.plain)
                .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .focused($isFieldFocused)
                .onSubmit {
                    submitCurrent()
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if !suggestions.isEmpty {
                        selectedIndex = (selectedIndex + 1) % suggestions.count
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.upArrow) {
                    if !suggestions.isEmpty {
                        selectedIndex = max(selectedIndex - 1, 0)
                        return .handled
                    }
                    return .ignored
                }

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .frame(minWidth: 260, maxWidth: 440)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        store.inlineURLBarFrame = geo.frame(in: .global)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        store.inlineURLBarFrame = newFrame
                    }
            }
        )
        .overlay(alignment: .topLeading) {
            if !suggestions.isEmpty && isFieldFocused {
                suggestionsDropdown
                    .offset(y: 32)
            }
        }
        .onAppear {
            text = tab.url?.absoluteString ?? ""
            isFieldFocused = true
            tab.webView.evaluateJavaScript("window.getSelection()?.removeAllRanges()", completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let textEditor = NSApp.keyWindow?.firstResponder as? NSTextView {
                    textEditor.setSelectedRange(NSRange(location: textEditor.string.count, length: 0))
                } else if let textEditor = NSApp.keyWindow?.firstResponder as? NSText {
                    textEditor.selectedRange = NSRange(location: textEditor.string.count, length: 0)
                }
            }
        }
        .onDisappear {
            store.inlineURLBarFrame = .zero
            store.inlineSuggestionsFrame = .zero
        }
        .onChange(of: suggestions.isEmpty) { _, isEmpty in
            if isEmpty {
                store.inlineSuggestionsFrame = .zero
            }
        }
        .onChange(of: isFieldFocused) { _, focused in
            if focused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if let textEditor = NSApp.keyWindow?.firstResponder as? NSTextView {
                        textEditor.setSelectedRange(NSRange(location: textEditor.string.count, length: 0))
                    } else if let textEditor = NSApp.keyWindow?.firstResponder as? NSText {
                        textEditor.selectedRange = NSRange(location: textEditor.string.count, length: 0)
                    }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if !isFieldFocused {
                        dismiss()
                    }
                }
            }
        }
    }

    private var suggestionsDropdown: some View {
        VStack(spacing: 1) {
            let items = Array(suggestions.prefix(6).enumerated())
            ForEach(items, id: \.element.id) { index, match in
                InlineSuggestionRow(
                    match: match,
                    icon: suggestionIcon(for: match),
                    isSelected: selectedIndex == index,
                    store: store
                ) {
                    execute(match)
                }
            }
        }
        .padding(4)
        .frame(width: 380)
        .background(
            store.adaptiveTheme.dropdownBackground,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(store.adaptiveTheme.dropdownStroke, lineWidth: 1)
        )
        .shadow(color: store.adaptiveTheme.dropdownShadow, radius: 12, x: 0, y: 4)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        store.inlineSuggestionsFrame = geo.frame(in: .global)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        store.inlineSuggestionsFrame = newFrame
                    }
            }
        )
        .onDisappear {
            store.inlineSuggestionsFrame = .zero
        }
    }

    private func submitCurrent() {
        if suggestions.indices.contains(selectedIndex) && !suggestions.isEmpty {
            execute(suggestions[selectedIndex])
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                tab.submit(trimmed)
            }
            dismiss()
        }
    }

    private func execute(_ match: OmnibarSuggestion) {
        if match.isSwitchToTab, let tabID = match.tabID {
            store.switchToTab(id: tabID)
        } else {
            tab.load(match.targetURL)
        }
        dismiss()
    }

    private func dismiss() {
        store.dismissInlineURLEditing()
    }
}

private struct InlineSuggestionRow: View {
    let match: OmnibarSuggestion
    let icon: String
    let isSelected: Bool
    let store: LeanStore
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(store.adaptiveTheme.secondaryText)
                .frame(width: 14)

            Text(match.primaryText)
                .font(store.leanUIFont.font(size: 12, weight: .regular))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .lineLimit(1)

            Spacer()

            Text(match.secondaryText)
                .font(store.leanUIFont.font(size: 11, weight: .regular))
                .foregroundColor(store.adaptiveTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? (store.adaptiveTheme.isFrameLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12))
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

private struct InteractiveIconButton: View {
    let systemImage: String
    let helpText: String
    let size: CGFloat
    let iconSize: CGFloat
    let color: Color
    var hoverColor: Color? = nil
    var disabledColor: Color? = nil
    var hoverBackground: Color? = nil
    var pressedBackground: Color? = nil
    let isDark: Bool
    var isEnabled = true
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    private var foregroundColor: Color {
        guard isEnabled else {
            return disabledColor ?? color.opacity(0.35)
        }
        if isHovered {
            return hoverColor ?? (isDark ? Color.white : Color.black)
        }
        return color
    }

    private var backgroundColor: Color {
        if isPressed {
            return pressedBackground ?? (isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))
        }
        if isHovered {
            return hoverBackground ?? (isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
        }
        return Color.clear
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .background(
                    backgroundColor,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
                .animation(.spring(response: 0.20, dampingFraction: 0.75), value: isHovered)
                .animation(.spring(response: 0.15, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(helpText)
        .onHover { isHovered = isEnabled && $0 }
    }
}
