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
                .background(WindowDragView())

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
                            icon: .plus,
                            helpText: "New Tab (⌘T)",
                            size: store.enableWindowBorder ? 26 : 24,
                            iconSize: 12,
                            color: store.adaptiveTheme.secondaryText,
                            hoverColor: store.adaptiveTheme.primaryText,
                            disabledColor: store.adaptiveTheme.disabledIconText,
                            hoverBackground: store.adaptiveTheme.iconHoverBackground,
                            pressedBackground: store.adaptiveTheme.iconPressedBackground,
                            isDark: store.adaptiveTheme.effectiveIsDark
                        ) {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                                _ = store.newTab()
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
                .background(WindowDragView())

            // Navigation Controls (Back, Forward, Reload) - Hidden on homepage or if not shown
            if store.selectedTab?.url != nil {
                let showBack = store.isToolbarItemShown(.back)
                let showForward = store.isToolbarItemShown(.forward)
                let showReload = store.isToolbarItemShown(.reload)

                if showBack || showForward || showReload {
                    HStack(spacing: 2) {
                        if showBack {
                            InteractiveIconButton(
                                icon: .caretLeft,
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
                                icon: .caretRight,
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
                                icon: .arrowClockwise,
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
            let showDownloads = store.isToolbarItemShown(.downloads)
            let showTheme = store.isToolbarItemShown(.themeToggle)
            let showSettings = store.isToolbarItemShown(.settings)

            if showDownloads || showTheme || showSettings {
                HStack(spacing: 2) {
                    if showDownloads {
                        DownloadToolbarButton(store: store)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(key: DownloadsButtonFrameKey.self, value: proxy.frame(in: .global))
                                }
                            )
                            .onPreferenceChange(DownloadsButtonFrameKey.self) { frame in
                                store.downloadsButtonFrame = frame
                            }
                    }

                    if showTheme {
                        InteractiveIconButton(
                            icon: store.isDarkMode ? .sun : .moon,
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
                            icon: .gear,
                            helpText: "Settings (⌘,)",
                            size: 24,
                            iconSize: 12,
                            color: store.isQuickSettingsPresented ? store.adaptiveTheme.primaryText : store.adaptiveTheme.secondaryText,
                            hoverColor: store.adaptiveTheme.primaryText,
                            disabledColor: store.adaptiveTheme.disabledIconText,
                            hoverBackground: store.adaptiveTheme.iconHoverBackground,
                            pressedBackground: store.adaptiveTheme.iconPressedBackground,
                            isDark: store.adaptiveTheme.effectiveIsDark
                        ) {
                            store.isQuickSettingsPresented.toggle()
                        }
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: SettingsButtonFrameKey.self, value: proxy.frame(in: .global))
                            }
                        )
                        .onPreferenceChange(SettingsButtonFrameKey.self) { frame in
                            store.settingsButtonFrame = frame
                        }
                    }
                }
            }

            Spacer().frame(width: 12)
        }
        .frame(height: store.scaled(store.enableWindowBorder ? 34 : 36))
        .background(
            store.enableWindowBorder
                ? AnyView(Color.clear)
                : AnyView(store.themeColors.topBarBackground)
        )
        // NOTE: no onTapGesture here on purpose. A tap gesture covering the
        // whole bar competes with every toolbar/tab Button inside it, forcing
        // double/triple clicks or pixel-hunting. Dismissing inline URL editing
        // on outside clicks is already handled by the global mouse monitor in
        // LeanView.setupKeyMonitor, which doesn't swallow the click.
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
    @State private var isFieldFocused = false

    private var showURLBar: Bool {
        isSelected && (isHovered || store.isInlineURLEditing || isFieldFocused)
    }

    private var showCloseOnHover: Bool {
        isHovered && !showURLBar
    }

    var body: some View {
        Button(action: handleTap) {
            tabContent
                .frame(height: store.scaled(store.enableWindowBorder ? 27 : 26))
        }
        .buttonStyle(.plain)
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
        .onHover { isHovered = $0 }
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
        .overlay(alignment: .trailing) {
            // Sibling overlay, NOT nested inside the select Button label,
            // so both Buttons hit-test independently with stable frames.
            if shouldShowClose && store.tabDisplayMode != .iconOnly {
                closeButton
                    .padding(.trailing, 6)
            }
        }
        .overlay(alignment: .center) {
            // Icon-only close replaces the favicon in place. Centered
            // sibling overlay for the same nested-Button reason: a close
            // Button inside iconOnlyContent (the select Button's label)
            // would never fire — the outer Button consumes the click.
            if shouldShowClose && store.tabDisplayMode == .iconOnly {
                closeButton
            }
        }
    }

    private var shouldShowClose: Bool {
        switch store.tabDisplayMode {
        case .textOnly, .hybrid:
            return isHovered && !showURLBar
        case .iconOnly:
            return showCloseOnHover
        }
    }

    private func handleTap() {
        if !isSelected {
            onSelect()
        } else if !store.isInlineURLEditing {
            store.isInlineURLEditing = true
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if showURLBar {
            InlineURLBar(
                tab: tab,
                store: store,
                autoFocus: store.isInlineURLEditing,
                isFocusedBinding: $isFieldFocused,
                onClose: onClose
            )
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
                .font(store.headingFont(size: 12.5))
                .foregroundColor(
                    isSelected
                        ? store.adaptiveTheme.activeTabText
                        : store.adaptiveTheme.inactiveTabText
                )
                .lineLimit(1)
            // Reserve close-button space so hover doesn't shift layout.
            Spacer(minLength: 0)
                .frame(width: 16)
        }
        .padding(.horizontal, 10)
        .padding(.trailing, 20)
    }

    @ViewBuilder
    private var iconOnlyContent: some View {
        // Fixed centered box: no HStack spacing artifact, no reserved
        // gap, no width shift on hover. The favicon hides when the
        // centered sibling overlay shows the close button in its place.
        TabFaviconView(tab: tab, isDark: store.adaptiveTheme.effectiveIsDark, size: 14)
            .opacity(shouldShowClose ? 0 : 1)
            .frame(width: store.scaled(28), height: store.scaled(26))
    }

    @ViewBuilder
    private var hybridContent: some View {
        HStack(spacing: 6) {
            TabFaviconView(tab: tab, isDark: store.adaptiveTheme.effectiveIsDark, size: 14)

            Text(tab.displayTitle(isSelected: isSelected, showFullTitle: store.showFullTitleOnActiveTab))
                .font(store.headingFont(size: 12.5))
                .foregroundColor(
                    isSelected
                        ? store.adaptiveTheme.activeTabText
                        : store.adaptiveTheme.inactiveTabText
                )
                .lineLimit(1)

            Spacer(minLength: 0)
                .frame(width: shouldShowClose ? 16 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.trailing, shouldShowClose ? 20 : 0)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Ph.x.bold
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: store.scaled(8), height: store.scaled(8))
                .foregroundColor(store.adaptiveTheme.tabCloseButtonForeground)
                .frame(width: store.scaled(18), height: store.scaled(18))
                .background(
                    store.adaptiveTheme.tabCloseButtonHoverBackground,
                    in: Circle()
                )
                // Rectangular hit area is larger and stable at the edges.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct InlineURLBar: View {
    @ObservedObject var tab: LeanTab
    @ObservedObject var store: LeanStore
    var autoFocus: Bool = false
    var isFocusedBinding: Binding<Bool>? = nil
    let onClose: () -> Void

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

    private func suggestionIcon(for match: OmnibarSuggestion) -> Ph {
        if match.isSearch {
            return .magnifyingGlass
        } else if match.isSwitchToTab {
            return .arrowCircleRight
        } else {
            return .browser
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            TabFaviconView(tab: tab, isDark: store.adaptiveTheme.effectiveIsDark, size: 13)

            TextField("Search or enter URL...", text: $text)
                .textFieldStyle(.plain)
                .font(store.headingFont(size: 12.5))
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
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        onClose()
                    }
                } label: {
                    Ph.xCircle.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Close Tab (⌘W)")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: store.scaled(26))
        .frame(minWidth: store.scaled(260), maxWidth: store.scaled(440))
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
            if autoFocus || store.isInlineURLEditing {
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
            isFocusedBinding?.wrappedValue = focused
            if focused {
                store.isInlineURLEditing = true
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

struct InlineSuggestionRow: View {
    let match: OmnibarSuggestion
    let icon: Ph
    let isSelected: Bool
    let store: LeanStore
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            icon.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .foregroundColor(store.adaptiveTheme.secondaryText)
                .frame(width: 14)

            Text(match.primaryText)
                .font(store.headingFont(size: 12))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .lineLimit(1)

            Spacer()

            Text(match.secondaryText)
                .font(store.bodyFont(size: 11))
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

struct InteractiveIconButton: View {
    @Environment(\.browserUIScale) private var browserUIScale

    let icon: Ph
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
            icon.uiIcon
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize * browserUIScale, height: iconSize * browserUIScale)
                .foregroundColor(foregroundColor)
                .frame(width: size * browserUIScale, height: size * browserUIScale)
                .background(
                    backgroundColor,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .contentShape(Rectangle())
                // Stable hit area: never grow on hover. Only a subtle press
                // shrink while held, so mouseUp always lands inside bounds.
                .scaleEffect(isPressed ? 0.93 : 1.0)
                .animation(.easeOut(duration: 0.08), value: isPressed)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(!isEnabled)
        .help(helpText)
        .onHover { isHovered = isEnabled && $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if isEnabled && !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - PreferenceKey for Settings Button Frame
struct SettingsButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - PreferenceKey for Downloads Button Frame
struct DownloadsButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Downloads Toolbar Button (sits beside the theme icon)
struct DownloadToolbarButton: View {
    @ObservedObject var store: LeanStore
    @Environment(\.browserUIScale) private var browserUIScale

    @State private var isHovered = false
    @State private var isPressed = false

    private var hasActive: Bool {
        store.downloadManager.hasActiveDownloads
    }

    private var foregroundColor: Color {
        if store.isDownloadsPresented {
            return store.adaptiveTheme.primaryText
        }
        if isHovered {
            return store.adaptiveTheme.primaryText
        }
        return store.adaptiveTheme.secondaryText
    }

    private var backgroundColor: Color {
        if isPressed {
            return store.adaptiveTheme.iconPressedBackground
        }
        if isHovered || store.isDownloadsPresented {
            return store.adaptiveTheme.iconHoverBackground
        }
        return Color.clear
    }

    var body: some View {
        Button {
            store.isQuickSettingsPresented = false
            store.isDownloadsPresented.toggle()
        } label: {
            ZStack {
                Ph.arrowCircleDown.fill
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12 * browserUIScale, height: 12 * browserUIScale)
                    .foregroundColor(foregroundColor)
                    .frame(width: 24 * browserUIScale, height: 24 * browserUIScale)
                    .background(
                        backgroundColor,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .scaleEffect(isPressed ? 0.93 : 1.0)
                    .animation(.easeOut(duration: 0.08), value: isPressed)

                if hasActive {
                    Capsule()
                        .fill(store.adaptiveTheme.secondaryText.opacity(0.25))
                        .frame(width: 12 * browserUIScale, height: 2 * browserUIScale)
                        .offset(y: 8 * browserUIScale)
                        .allowsHitTesting(false)
                    Capsule()
                        .fill(store.isDarkMode ? Color.white : Color.black)
                        .frame(width: 12 * CGFloat(store.downloadManager.overallProgress) * browserUIScale, height: 2 * browserUIScale)
                        .offset(y: 8 * browserUIScale)
                        .allowsHitTesting(false)
                } else if !store.downloadManager.downloads.isEmpty {
                    Circle()
                        .fill(store.adaptiveTheme.secondaryText.opacity(0.55))
                        .frame(width: 4 * browserUIScale, height: 4 * browserUIScale)
                        .offset(x: 7 * browserUIScale, y: -7 * browserUIScale)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(downloadsHelpText)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }

    private var downloadsHelpText: String {
        let active = store.downloadManager.activeDownloads.count
        if active > 0 {
            return "Downloads (\(active) active — click to view)"
        }
        let total = store.downloadManager.downloads.count
        if total > 0 {
            return "Downloads (\(total)) — click to view"
        }
        return "Downloads"
    }
}

// MARK: - History Row Y Preference Key
private struct HistoryRowYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 142
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

// MARK: - Bespoke Quick Settings Popover
struct QuickSettingsPopover: View {
    @ObservedObject var store: LeanStore

    @State private var isHistoryHovered = false
    @State private var isSubmenuHovered = false
    @State private var isSubmenuVisible = false
    @State private var isAllSettingsHovered = false
    @State private var historyRowY: CGFloat = 142
    @State private var closeWorkItem: DispatchWorkItem? = nil

    private func onHistoryHoverChanged(_ hovering: Bool) {
        isHistoryHovered = hovering
        if hovering {
            closeWorkItem?.cancel()
            closeWorkItem = nil
            if !isSubmenuVisible {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                    isSubmenuVisible = true
                }
            }
        } else {
            scheduleCloseIfNeeded()
        }
    }

    private func onSubmenuHoverChanged(_ hovering: Bool) {
        isSubmenuHovered = hovering
        if hovering {
            closeWorkItem?.cancel()
            closeWorkItem = nil
        } else {
            scheduleCloseIfNeeded()
        }
    }

    private func scheduleCloseIfNeeded() {
        closeWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            if !isHistoryHovered && !isSubmenuHovered {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                    isSubmenuVisible = false
                }
            }
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func handleNonHistoryHovered(_ hovering: Bool) {
        if hovering {
            closeWorkItem?.cancel()
            closeWorkItem = nil
            isHistoryHovered = false
            if isSubmenuVisible {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                    isSubmenuVisible = false
                }
            }
        }
    }

    var body: some View {
        mainPopoverCard
            .overlay(alignment: .topLeading) {
                if isSubmenuVisible {
                    HStack(spacing: 0) {
                        QuickSettingsHistorySubmenu(
                            store: store,
                            onHoverChanged: onSubmenuHoverChanged,
                            onOpenHistoryTab: {
                                withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                                    store.isQuickSettingsPresented = false
                                }
                                store.openSettings(category: .history)
                            }
                        )

                        // Seamless invisible hover bridge between submenu and main popover
                        Color.clear
                            .frame(width: 8)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering {
                                    closeWorkItem?.cancel()
                                    closeWorkItem = nil
                                } else {
                                    scheduleCloseIfNeeded()
                                }
                            }
                    }
                    .fixedSize()
                    .offset(x: -248, y: max(0, historyRowY - 6))
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity)
                    ))
                }
            }
            .coordinateSpace(name: "QuickSettingsCard")
            .onPreferenceChange(HistoryRowYPreferenceKey.self) { y in
                if y > 0 {
                    historyRowY = y
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            store.quickSettingsPopoverFrame = proxy.frame(in: .global)
                        }
                        .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                            store.quickSettingsPopoverFrame = newFrame
                        }
                }
            )
            .onDisappear {
                closeWorkItem?.cancel()
                closeWorkItem = nil
                isSubmenuVisible = false
                isHistoryHovered = false
                isSubmenuHovered = false
                store.quickSettingsPopoverFrame = .zero
                store.quickSettingsSubmenuFrame = .zero
            }
    }

    private var mainPopoverCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Quick Toggles starting directly from Zen mode
            VStack(spacing: 2) {
                QuickToggleItem(
                    icon: .slidersHorizontal,
                    title: "Zen mode",
                    isOn: $store.enableZenMode,
                    isDark: store.isDarkMode,
                    uiFont: store.leanUIFont,
                    onHoverChanged: handleNonHistoryHovered
                )

                if store.tabLayout != .sidebar {
                    QuickToggleItem(
                        icon: .browser,
                        title: "Window frame",
                        isOn: $store.enableWindowBorder,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont,
                        onHoverChanged: handleNonHistoryHovered
                    )
                }

                QuickToggleItem(
                    icon: .shield,
                    title: "Ad & tracker filter",
                    isOn: $store.adBlockingEnabled,
                    isDark: store.isDarkMode,
                    uiFont: store.leanUIFont,
                    accentColor: Color(red: 52/255, green: 199/255, blue: 89/255),
                    onHoverChanged: handleNonHistoryHovered
                )

                QuickToggleItem(
                    icon: .mouse,
                    title: "Smooth scrolling",
                    isOn: $store.smoothScrollingEnabled,
                    isDark: store.isDarkMode,
                    uiFont: store.leanUIFont,
                    onHoverChanged: handleNonHistoryHovered
                )
            }

            Rectangle()
                .fill(store.themeColors.divider)
                .frame(height: 0.75)
                .padding(.vertical, 2)

            // History Settings and All Settings
            VStack(spacing: 2) {
                QuickSettingsHistoryRow(
                    isDark: store.isDarkMode,
                    uiFont: store.leanUIFont,
                    isSubmenuOpen: isSubmenuVisible,
                    onHoverChanged: onHistoryHoverChanged,
                    onSelect: {
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                            store.isQuickSettingsPresented = false
                        }
                        store.openSettings(category: .history)
                    }
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: HistoryRowYPreferenceKey.self, value: proxy.frame(in: .named("QuickSettingsCard")).minY)
                    }
                )

                // Bottom link to All Settings
                Button {
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                        store.isQuickSettingsPresented = false
                    }
                    store.openSettings()
                } label: {
                    HStack(spacing: 8) {
                        Ph.gear.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                        Text("All Settings...")
                            .font(store.headingFont(size: 12))
                        Spacer()
                        Text("⌘,")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(store.adaptiveTheme.secondaryText)
                        Ph.caretRight.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 8, height: 8)
                            .foregroundColor(store.adaptiveTheme.secondaryText)
                    }
                    .foregroundColor(store.adaptiveTheme.primaryText)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        isAllSettingsHovered
                            ? (store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isAllSettingsHovered = hovering
                    handleNonHistoryHovered(hovering)
                }
            }
        }
        .padding(8)
        .frame(width: 228)
        .background(
            (store.isDarkMode
                ? Color(red: 18/255, green: 18/255, blue: 21/255)
                : Color(white: 0.995)
            ).opacity(0.97)
        )
        .background(
            VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(store.adaptiveTheme.dropdownStroke, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(store.isDarkMode ? 0.45 : 0.12), radius: 18, x: 0, y: 8)
        .shadow(color: Color.black.opacity(store.isDarkMode ? 0.20 : 0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Quick Settings History Row
struct QuickSettingsHistoryRow: View {
    let isDark: Bool
    let uiFont: LeanFont
    let isSubmenuOpen: Bool
    let onHoverChanged: (Bool) -> Void
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Ph.clock.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundColor(isDark ? Color.white.opacity(0.70) : Color.black.opacity(0.60))
                    .frame(width: 16)

                Text("History")
                    .font(uiFont.font(size: 12, weight: .regular))
                    .foregroundColor(isDark ? Color(white: 0.92) : Color(white: 0.14))

                Spacer()

                Ph.caretRight.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 8, height: 8)
                    .foregroundColor(isDark ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                (isHovered || isSubmenuOpen)
                    ? (isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(hovering)
        }
    }
}

// MARK: - Bespoke Quick Settings History Submenu
struct QuickSettingsHistorySubmenu: View {
    @ObservedObject var store: LeanStore
    let onHoverChanged: (Bool) -> Void
    let onOpenHistoryTab: () -> Void

    @State private var isViewAllHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let recentItems = Array(store.historyItems.prefix(6))

            if recentItems.isEmpty {
                HStack(spacing: 8) {
                    Ph.clock.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .frame(width: 14)
                    Text("No Recent History")
                        .font(store.leanUIFont.font(size: 11.5))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
            } else {
                ForEach(recentItems) { item in
                    QuickSettingsHistorySubmenuItem(
                        item: item,
                        store: store,
                        onSelect: {
                            let inNewTab = NSEvent.modifierFlags.contains(.command)
                            store.openHistoryItem(item, inNewTab: inNewTab)
                            withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                                store.isQuickSettingsPresented = false
                            }
                        }
                    )
                }
            }

            Rectangle()
                .fill(store.themeColors.divider)
                .frame(height: 0.75)
                .padding(.vertical, 3)

            // Option to view all which opens the history tab in the settings
            Button(action: onOpenHistoryTab) {
                HStack(spacing: 8) {
                    Ph.clockCounterClockwise.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .frame(width: 14)

                    Text("View All History...")
                        .font(store.headingFont(size: 11.5))
                        .foregroundColor(store.adaptiveTheme.primaryText)

                    Spacer()

                    Ph.caretRight.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 8, height: 8)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    isViewAllHovered
                        ? (store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isViewAllHovered = $0 }
        }
        .padding(6)
        .frame(width: 240)
        .background(
            (store.isDarkMode
                ? Color(red: 18/255, green: 18/255, blue: 21/255)
                : Color(white: 0.995)
            ).opacity(0.97)
        )
        .background(
            VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(store.adaptiveTheme.dropdownStroke, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(store.isDarkMode ? 0.45 : 0.12), radius: 18, x: 0, y: 8)
        .shadow(color: Color.black.opacity(store.isDarkMode ? 0.20 : 0.04), radius: 2, x: 0, y: 1)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        store.quickSettingsSubmenuFrame = proxy.frame(in: .global)
                    }
                    .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                        store.quickSettingsSubmenuFrame = newFrame
                    }
            }
        )
        .onDisappear {
            store.quickSettingsSubmenuFrame = .zero
        }
        .onHover { hovering in
            onHoverChanged(hovering)
        }
    }
}

// MARK: - Bespoke Quick Settings History Submenu Item
private struct QuickSettingsHistorySubmenuItem: View {
    let item: HistoryItem
    @ObservedObject var store: LeanStore
    let onSelect: () -> Void

    @State private var isHovered = false

    private var displayTitle: String {
        let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let host = item.url.host, !host.isEmpty {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return item.url.absoluteString
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                SiteFaviconView(url: item.url, isDark: store.isDarkMode, size: 13)
                    .frame(width: 14, height: 14)

                Text(displayTitle)
                    .font(store.leanUIFont.font(size: 11.5, weight: .regular))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                isHovered
                    ? (store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(item.title)\n\(item.url.absoluteString)")
        .onHover { isHovered = $0 }
    }
}

// MARK: - Quick Toggle Item
struct QuickToggleItem: View {
    let icon: Ph
    let title: String
    @Binding var isOn: Bool
    let isDark: Bool
    let uiFont: LeanFont
    var accentColor: Color? = nil
    var onHoverChanged: ((Bool) -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                icon.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 13, height: 13)
                    .foregroundColor(
                        isOn
                            ? (accentColor ?? (isDark ? Color.white : Color.black))
                            : (isDark ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                    )
                    .frame(width: 16)

                Text(title)
                    .font(uiFont.font(size: 12, weight: .regular))
                    .foregroundColor(isDark ? Color(white: 0.92) : Color(white: 0.14))

                Spacer()

                // Minimal micro switch
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(
                            isOn
                                ? (accentColor ?? (isDark ? Color.white : Color(white: 0.10)))
                                : (isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                        )
                        .frame(width: 28, height: 16)

                    Circle()
                        .fill(
                            isOn
                                ? (isDark ? Color(white: 0.08) : Color.white)
                                : (isDark ? Color.white.opacity(0.85) : Color.white)
                        )
                        .frame(width: 11, height: 11)
                        .padding(2.5)
                        .shadow(color: Color.black.opacity(0.18), radius: 1, y: 0.5)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                isHovered
                    ? (isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged?(hovering)
        }
    }
}

