import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sidebar View for Vertical Tabs
struct SidebarView: View {
    @ObservedObject var store: LeanStore
    @Namespace private var sidebarTabSelectionNamespace

    private var sidebarBackground: Color {
        // With a window border the sidebar is part of the coloured frame.
        store.enableWindowBorder ? Color.clear : store.frameBackground
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Header Row: Custom Titlebar with Traffic Lights + Sidebar Toggle Button
            HStack(spacing: 0) {
                SidebarTrafficLights(store: store)
                    .padding(.leading, 14)

                Spacer(minLength: 0)
                    .background(WindowDragView())

                InteractiveIconButton(
                    icon: .sidebar,
                    helpText: store.isSidebarCollapsed ? "Pin Sidebar (Always Expanded) (⌘S)" : "Enable Auto-hide (⌘S)",
                    size: 26,
                    iconSize: 13,
                    color: store.isSidebarCollapsed ? store.adaptiveTheme.secondaryText : store.adaptiveTheme.primaryText,
                    hoverColor: store.adaptiveTheme.primaryText,
                    hoverBackground: store.adaptiveTheme.iconHoverBackground,
                    pressedBackground: store.adaptiveTheme.iconPressedBackground,
                    isDark: store.adaptiveTheme.effectiveIsDark
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.toggleSidebar()
                    }
                }
                .padding(.trailing, 10)
            }
            .frame(height: store.scaled(38))
            .padding(.top, store.scaled(6))

            // 2. Full-Width Interactive Omnibar / Address Field
            SidebarAddressBar(store: store)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, store.pinnedTabs.isEmpty ? 10 : 8)
                .zIndex(10)

            // 3. Pinned Tabs Grid (Positioned above TABS + row)
            if !store.pinnedTabs.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(store.pinnedTabs) { tab in
                        SidebarPinnedTabItem(
                            tab: tab,
                            isSelected: tab.id == store.selectedID,
                            namespace: sidebarTabSelectionNamespace,
                            store: store,
                            onSelect: { handleTabSelection(tab) },
                            onClose: { store.close(tab) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

            // 4. Section Title Row with + New Tab Icon
            HStack(spacing: 6) {
                Text("Tabs")
                    .font(store.headingFont(size: 11, weight: .bold))
                    .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.85))
                    .textCase(.uppercase)
                    .kerning(0.8)

                Spacer()

                InteractiveIconButton(
                    icon: .plus,
                    helpText: "New Tab (⌘T)",
                    size: 24,
                    iconSize: 12,
                    color: store.adaptiveTheme.secondaryText,
                    hoverColor: store.adaptiveTheme.primaryText,
                    hoverBackground: store.adaptiveTheme.iconHoverBackground,
                    pressedBackground: store.adaptiveTheme.iconPressedBackground,
                    isDark: store.adaptiveTheme.effectiveIsDark
                ) {
                    _ = store.newTab()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            // 5. Vertical Tab Strip (Unpinned tabs)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    if store.tabDisplayMode == .iconOnly {
                        iconTabRuns
                    } else {
                        ForEach(store.unpinnedTabs) { tab in
                            tabRow(tab)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            Spacer(minLength: 0)

            // 6. Bottom Footer Row: Downloads, Theme toggle, Settings, New Tab
            HStack(spacing: 6) {
                ExtensionToolbarButton(store: store)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: ExtensionsButtonFrameKey.self, value: proxy.frame(in: .global))
                        }
                    )
                    .onPreferenceChange(ExtensionsButtonFrameKey.self) { frame in
                        store.extensionsButtonFrame = frame
                    }

                BookmarkToolbarButton(store: store)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: BookmarksButtonFrameKey.self, value: proxy.frame(in: .global))
                        }
                    )
                    .onPreferenceChange(BookmarksButtonFrameKey.self) { frame in
                        store.bookmarksButtonFrame = frame
                    }

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

                Spacer()

                InteractiveIconButton(
                    icon: store.isDarkMode ? .sun : .moon,
                    helpText: store.isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode",
                    size: 24,
                    iconSize: 12,
                    color: store.adaptiveTheme.secondaryText,
                    hoverColor: store.adaptiveTheme.primaryText,
                    hoverBackground: store.adaptiveTheme.iconHoverBackground,
                    pressedBackground: store.adaptiveTheme.iconPressedBackground,
                    isDark: store.adaptiveTheme.effectiveIsDark
                ) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        store.toggleTheme()
                    }
                }

                InteractiveIconButton(
                    icon: .gear,
                    helpText: "Settings (⌘,)",
                    size: 24,
                    iconSize: 12,
                    color: store.isQuickSettingsPresented ? store.adaptiveTheme.primaryText : store.adaptiveTheme.secondaryText,
                    hoverColor: store.adaptiveTheme.primaryText,
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
            .frame(height: store.scaled(38))
            .padding(.horizontal, store.scaled(10))
            .padding(.bottom, store.scaled(4))
        }
        .frame(width: store.scaled(256))
        .background {
            if store.liquidGlassEnabled, #available(macOS 26, *) {
                Color.clear.glassEffect()
            } else {
                sidebarBackground
            }
        }
    }

    private func tabRow(_ tab: LeanTab) -> some View {
        SidebarTabItem(
            tab: tab,
            isSelected: tab.id == store.selectedID,
            namespace: sidebarTabSelectionNamespace,
            store: store,
            onSelect: { handleTabSelection(tab) },
            onClose: { store.close(tab) }
        )
    }

    /// Icon-only: plain tabs become a grid of square tiles. A split tab shows
    /// several icons, so it keeps a full-width row and breaks the grid.
    private var iconTabRuns: some View {
        let runs = store.unpinnedTabs.reduce(into: [[LeanTab]]()) { runs, tab in
            if tab.isSplit || runs.last?.first?.isSplit != false {
                runs.append([tab])
            } else {
                runs[runs.count - 1].append(tab)
            }
        }
        return ForEach(runs, id: \.first?.id) { run in
            if let first = run.first, first.isSplit {
                tabRow(first)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(run) { tab in
                        SidebarPinnedTabItem(
                            tab: tab,
                            isSelected: tab.id == store.selectedID,
                            namespace: sidebarTabSelectionNamespace,
                            store: store,
                            isRoomy: true,
                            onSelect: { handleTabSelection(tab) },
                            onClose: { store.close(tab) }
                        )
                    }
                }
            }
        }
    }

    private func handleTabSelection(_ tab: LeanTab) {
        if tab.id == store.selectedID {
            NotificationCenter.default.post(name: .focusAddress, object: nil)
        } else {
            withAnimation(Motion.tabSwitch) {
                store.switchToTab(id: tab.id)
            }
        }
    }
}

// MARK: - Sidebar Address / Omnibar Field
private struct SidebarAddressBar: View {
    @ObservedObject var store: LeanStore
    @FocusState private var isFocused: Bool
    @State private var text = ""
    @State private var selectedIndex = 0
    /// What the user typed; suggestions come from this, not from `text`, which
    /// shows the highlighted suggestion while arrowing through the list.
    @State private var query = ""
    @State private var appliedSuggestionText: String?
    @State private var didCopyLink = false

    private var openTabsForSuggestions: [(id: UUID, title: String, url: URL)] {
        store.tabs.compactMap { t in
            guard let url = t.url, t.id != store.selectedID else { return nil }
            return (id: t.id, title: t.title, url: url)
        }
    }

    private var suggestions: [OmnibarSuggestion] {
        guard !query.isEmpty else { return [] }
        return OmnibarService.shared.suggestions(
            for: query,
            history: store.visitedHistory,
            openTabs: openTabsForSuggestions,
            searchEngine: store.searchEngine
        )
    }

    private var addressField: some View {
        TextField("Search or Enter URL...", text: $text)
            .textFieldStyle(.plain)
            .font(store.bodyFont(size: 13))
            .foregroundColor(store.adaptiveTheme.primaryText)
            .focused($isFocused)
            .onSubmit {
                submitCurrent()
            }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
            .onKeyPress(.downArrow) {
                if !suggestions.isEmpty {
                    select((selectedIndex + 1) % suggestions.count)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.upArrow) {
                if !suggestions.isEmpty {
                    select(max(selectedIndex - 1, 0))
                    return .handled
                }
                return .ignored
            }
    }

    @ViewBuilder
    private var barBackground: some View {
        if store.liquidGlassEnabled, #available(macOS 26, *) {
            Color.clear.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isFocused
                                ? (store.themeColors.accent ?? store.adaptiveTheme.primaryText.opacity(0.5))
                                : (store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                            lineWidth: isFocused ? 1.5 : 1
                        )
                )
        }
    }

    /// Drawn by LeanView at the window root: the sidebar card clips and
    /// z-orders anything drawn from here.
    private func syncDropdown() {
        guard isFocused, !suggestions.isEmpty else {
            if store.suggestionDropdown?.owner == .sidebarBar { store.suggestionDropdown = nil }
            return
        }
        store.suggestionDropdown = SuggestionDropdown(
            owner: .sidebarBar,
            width: nil,
            matches: Array(suggestions.prefix(6)),
            selectedIndex: selectedIndex,
            onSelect: execute
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            LeanIcon.magnifyingGlass.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .foregroundColor(store.adaptiveTheme.secondaryText)

            addressField

            Spacer(minLength: 4)

            if isFocused && !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    LeanIcon.xCircle.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hitArea)
                .contentShape(Rectangle())
            } else if store.selectedTab?.url != nil {
                // Copy link button
                Button {
                    if let url = store.selectedTab?.url {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        didCopyLink = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            didCopyLink = false
                        }
                    }
                } label: {
                    (didCopyLink ? LeanIcon.check.bold : LeanIcon.copy.fill)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundColor(didCopyLink ? Color.green : store.adaptiveTheme.secondaryText)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hitArea)
                .contentShape(Rectangle())
                .help("Copy Page Link")
            }
        }
        .padding(.horizontal, store.scaled(10))
        .frame(height: store.scaled(36))
        .background(barBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
        .anchorPreference(key: SuggestionAnchorKey.self, value: .bounds) { [.sidebarBar: $0] }
        .onChange(of: text) { _, _ in
            textDidChange()
            syncDropdown()
        }
        .onChange(of: selectedIndex) { _, _ in syncDropdown() }
        .onChange(of: isFocused) { _, _ in syncDropdown() }
        .onDisappear {
            if store.suggestionDropdown?.owner == .sidebarBar { store.suggestionDropdown = nil }
        }
        .onAppear {
            syncFromTab()
        }
        .onChange(of: store.selectedID) { _, _ in
            syncFromTab()
        }
        .onChange(of: store.selectedTab?.url) { _, _ in
            syncFromTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddress)) { _ in
            startEditing()
        }
    }

    private func syncFromTab() {
        if !isFocused {
            if let url = store.selectedTab?.url {
                text = url.absoluteString
            } else {
                text = ""
            }
        }
    }

    private func startEditing() {
        if let url = store.selectedTab?.url {
            text = url.absoluteString
        }
        isFocused = true
    }

    /// Highlights a suggestion and shows it in the field right away.
    private func select(_ index: Int) {
        guard suggestions.indices.contains(index) else { return }
        selectedIndex = index
        let match = suggestions[index]
        let shown = match.isSearch ? match.primaryText : match.targetURL.absoluteString
        appliedSuggestionText = shown
        text = shown
    }

    private func textDidChange() {
        if text == appliedSuggestionText { return }
        appliedSuggestionText = nil
        query = text
        selectedIndex = 0
    }

    private func submitCurrent() {
        if suggestions.indices.contains(selectedIndex) && !suggestions.isEmpty {
            execute(suggestions[selectedIndex])
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let tab = store.selectedTab {
                    tab.submit(trimmed)
                } else {
                    _ = store.newTab(url: URL(string: trimmed))
                }
            }
            dismiss()
        }
    }

    private func execute(_ match: OmnibarSuggestion) {
        if match.isSwitchToTab, let tabID = match.tabID {
            store.switchToTab(id: tabID)
        } else if let tab = store.selectedTab {
            tab.load(match.targetURL)
        } else {
            _ = store.newTab(url: match.targetURL)
        }
        dismiss()
    }

    private func dismiss() {
        isFocused = false
        syncFromTab()
    }
}

// MARK: - Sidebar Tab Item
struct SidebarTabItem: View {
    @ObservedObject var tab: LeanTab
    let isSelected: Bool
    var namespace: Namespace.ID
    @ObservedObject var store: LeanStore
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var isDropTarget = false

    private var showsClose: Bool {
        isHovered || isSelected
    }

    private var tabItemForeground: Color {
        isSelected
            ? store.adaptiveTheme.activeTabText
            : (isHovered ? store.adaptiveTheme.primaryText : store.adaptiveTheme.inactiveTabText)
    }

    var body: some View {
        Button(action: onSelect) {
            Group {
                if tab.isSplit {
                    splitSidebarContent
                } else {
                    defaultSidebarContent
                }
            }
            .padding(.horizontal, store.scaled(10))
            .frame(height: store.scaled(36))
        }
        .buttonStyle(.hitArea)
        .overlay { TabMiddleClick { onClose() } }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected && store.liquidGlassEnabled ? Color.clear : (isHovered ? (store.isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.05)) : Color.clear))

                if isSelected {
                    if store.liquidGlassEnabled, #available(macOS 26, *) {
                        Color.clear.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onDrag {
            store.draggingTabID = tab.id
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: TabReorderDropDelegate(targetID: tab.id, store: store) { isDropTarget = $0 }
        )
        .overlay(alignment: .leading) {
            if isDropTarget {
                Capsule()
                    .fill(store.adaptiveTheme.primaryText)
                    .frame(width: 2)
                    .padding(.vertical, 7)
                    .padding(.leading, 2)
            }
        }
        .onHover { isHovered = $0 }
        .overlay(alignment: .trailing) {
            if showsClose {
                Button(action: onClose) {
                    LeanIcon.x.bold
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: store.scaled(8), height: store.scaled(8))
                        .foregroundColor(store.adaptiveTheme.tabCloseButtonForeground)
                        .frame(width: store.scaled(20), height: store.scaled(20))
                        .background(
                            store.adaptiveTheme.tabCloseButtonHoverBackground,
                            in: Circle()
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hitArea)
                .contentShape(Rectangle())
                .help("Close Tab (⌘W)")
                .padding(.trailing, 8)
            }
        }
        .contextMenu {
            if tab.isPlayingMedia {
                Button {
                    tab.toggleMute()
                } label: {
                    Label(tab.isMuted ? "Unmute Tab" : "Mute Tab", systemImage: tab.isMuted ? "speaker.wave.2" : "speaker.slash")
                }
                Divider()
            }
            if tab.isSplit {
                Button {
                    store.separateSplitTabs(tab)
                } label: {
                    Label("Separate Tabs", systemImage: "rectangle.split.2x1.slash")
                }
                Button {
                    store.close(tab)
                } label: {
                    Label("Close Split", systemImage: "xmark")
                }
                Divider()
            } else {
                if let active = store.selectedTab, active.isSplit, active.splitTabs.count < 4, tab.id != active.id {
                    let parent = active
                    Button {
                        store.addTabToSplit(parent, tabToAdd: tab)
                    } label: {
                        Label("Add to Split", systemImage: "square.split.2x1")
                    }
                    Divider()
                } else if tab.url != nil, !(store.selectedTab?.isSplit == true) {
                    if let active = store.selectedTab, active.id != tab.id, !active.isSplit {
                        let parent = active
                        Button {
                            store.openTabsAsSplit(parent, tab)
                        } label: {
                            Label("Open as Split", systemImage: "square.split.2x1")
                        }
                    } else {
                        Button {
                            store.openTabAsSplit(tab)
                        } label: {
                            Label("Open as Split", systemImage: "square.split.2x1")
                        }
                    }
                    Divider()
                }
            }
            if tab.url != nil && !tab.isSplit {
                Button {
                    store.togglePin(tab: tab)
                } label: {
                    Label(tab.isPinned ? "Unpin" : "Pin", systemImage: tab.isPinned ? "pin.slash" : "pin")
                }
                Divider()
            }
            if tab.isSleeping {
                Button("Wake Tab", action: onSelect)
            } else {
                Button("Sleep Tab") { store.sleepTab(tab, notifyOnFailure: true) }
                    .disabled(isSelected)
            }
            Button("Close Tab", action: onClose)
            Button("Close Other Tabs") {
                for otherTab in store.tabs where otherTab.id != tab.id {
                    store.close(otherTab)
                }
            }
            Divider()
            Button("Reload") { tab.reload() }
            if tab.canGoBack {
                Button("Back") { tab.goBack() }
            }
            if tab.canGoForward {
                Button("Forward") { tab.goForward() }
            }
            Divider()
            Button("Duplicate Tab") {
                if let url = tab.url {
                    _ = store.newTab(url: url)
                } else {
                    _ = store.newTab()
                }
            }
        }
    }

    @ViewBuilder
    private var defaultSidebarContent: some View {
        switch store.tabDisplayMode {
        case .hybrid:
            HStack(spacing: 8) {
                ZStack {
                    if tab.isLoading {
                        DotMatrixLoader(
                            color: tabItemForeground,
                            size: store.scaled(16)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    } else {
                        TabFaviconView(tab: tab, isDark: store.adaptiveTheme.effectiveIsDark, size: 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .frame(width: store.scaled(16), height: store.scaled(16))
                .scaleEffect(isSelected ? 1.05 : 0.96)

                .animation(.easeInOut(duration: 0.2), value: tab.isLoading)

                Text(tab.displayTitle(isSelected: isSelected, showFullTitle: true))
                    .font(store.tabTitleFont(size: 13))
                    .foregroundColor(tabItemForeground)
                    .scaleEffect(isSelected ? 1.0 : 0.985)
    
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if tab.isPlayingMedia {
                    TabMediaIndicatorView(tab: tab, theme: store.adaptiveTheme, compact: false)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }

                // Always reserve close-button width so hover doesn't push text.
                Color.clear.frame(width: 18, height: 18)
            }
        case .iconOnly:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    if tab.isLoading {
                        DotMatrixLoader(
                            color: tabItemForeground,
                            size: store.scaled(16)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    } else {
                        TabFaviconView(tab: tab, isDark: store.adaptiveTheme.effectiveIsDark, size: 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .frame(width: store.scaled(16), height: store.scaled(16))
                .scaleEffect(isSelected ? 1.08 : 0.95)

                .animation(.easeInOut(duration: 0.2), value: tab.isLoading)

                Spacer(minLength: 0)
            }
        case .textOnly:
            HStack(spacing: 8) {
                if tab.isLoading {
                    DotMatrixLoader(
                        color: tabItemForeground,
                        size: store.scaled(14)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }

                Text(tab.displayTitle(isSelected: isSelected, showFullTitle: true))
                    .font(store.tabTitleFont(size: 13))
                    .foregroundColor(tabItemForeground)
                    .scaleEffect(isSelected ? 1.0 : 0.985)
    
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if tab.isPlayingMedia {
                    TabMediaIndicatorView(tab: tab, theme: store.adaptiveTheme, compact: false)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }

                Color.clear.frame(width: 18, height: 18)
            }
        }
    }

    @ViewBuilder
    private var splitSidebarContent: some View {
        switch store.tabDisplayMode {
        case .hybrid:
            HStack(spacing: 0) {
                ForEach(Array(tab.splitTabs.enumerated()), id: \.element.id) { index, subTab in
                    let isSubActive = (index == tab.activeSplitIndex)
                    Button {
                        tab.activeSplitIndex = index
                        onSelect()
                    } label: {
                        HStack(spacing: 5) {
                            TabFaviconView(tab: subTab, isDark: store.adaptiveTheme.effectiveIsDark, size: 13)
                            Text(subTab.displayTitle(isSelected: isSelected && isSubActive, showFullTitle: false))
                                .font(store.tabTitleFont(size: 12))
                                .foregroundColor(
                                    isSubActive && isSelected
                                        ? store.adaptiveTheme.activeTabText
                                        : store.adaptiveTheme.inactiveTabText
                                )
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            isSubActive && isSelected
                                ? store.adaptiveTheme.splitHighlightColor.opacity(0.18)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                    }
                    .buttonStyle(.hitArea)

                    if index < tab.splitTabs.count - 1 {
                        Rectangle()
                            .fill(store.adaptiveTheme.activeTabStroke.opacity(0.25))
                            .frame(width: 1, height: 12)
                            .padding(.horizontal, 2)
                    }
                }

                Spacer(minLength: 4)

                if tab.isPlayingMedia {
                    TabMediaIndicatorView(tab: tab, theme: store.adaptiveTheme, compact: false)
                }

                Color.clear.frame(width: 18, height: 18)
            }

        case .iconOnly:
            HStack(spacing: 4) {
                ForEach(Array(tab.splitTabs.enumerated()), id: \.element.id) { index, subTab in
                    let isSubActive = (index == tab.activeSplitIndex)
                    Button {
                        tab.activeSplitIndex = index
                        onSelect()
                    } label: {
                        TabFaviconView(tab: subTab, isDark: store.adaptiveTheme.effectiveIsDark, size: 14)
                            .padding(2)
                            .background(
                                isSubActive && isSelected
                                    ? store.adaptiveTheme.splitHighlightColor.opacity(0.22)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            )
                    }
                    .buttonStyle(.hitArea)
                }

                Spacer(minLength: 4)
                Color.clear.frame(width: 18, height: 18)
            }

        case .textOnly:
            HStack(spacing: 4) {
                ForEach(Array(tab.splitTabs.enumerated()), id: \.element.id) { index, subTab in
                    let isSubActive = (index == tab.activeSplitIndex)
                    Button {
                        tab.activeSplitIndex = index
                        onSelect()
                    } label: {
                        Text(subTab.displayTitle(isSelected: isSelected && isSubActive, showFullTitle: false))
                            .font(store.tabTitleFont(size: 12))
                            .foregroundColor(
                                isSubActive && isSelected
                                    ? store.adaptiveTheme.activeTabText
                                    : store.adaptiveTheme.inactiveTabText
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .buttonStyle(.hitArea)

                    if index < tab.splitTabs.count - 1 {
                        Text("|")
                            .font(.system(size: 10, weight: .light))
                            .foregroundColor(store.adaptiveTheme.inactiveTabText.opacity(0.4))
                    }
                }

                Spacer(minLength: 4)
                Color.clear.frame(width: 18, height: 18)
            }
        }
    }
}

// MARK: - Sidebar Pinned Tab Item (Grid tile with centered favicon)
private struct SidebarPinnedTabItem: View {
    @ObservedObject var tab: LeanTab
    let isSelected: Bool
    var namespace: Namespace.ID
    @ObservedObject var store: LeanStore
    /// Icon-only mode reuses this tile for every tab: bigger, and closable on hover.
    var isRoomy = false
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var isDropTarget = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                if tab.isLoading {
                    DotMatrixLoader(
                        color: isSelected ? store.adaptiveTheme.activeTabText : store.adaptiveTheme.primaryText,
                        size: store.scaled(isRoomy ? 18 : 14)
                    )
                } else {
                    TabFaviconView(tab: tab, isDark: store.adaptiveTheme.effectiveIsDark, size: isRoomy ? 20 : 16)
                }
            }
            .scaleEffect(isSelected ? 1.06 : 0.95)
            .frame(maxWidth: .infinity)
            .frame(height: store.scaled(isRoomy ? 44 : 38))
            .background {
                ZStack {
                    if store.liquidGlassEnabled, #available(macOS 26, *) {
                        Color.clear.glassEffect(
                            isSelected ? .regular.interactive() : .clear.interactive(),
                            in: .rect(cornerRadius: 8)
                        )
                    } else {
                        if isHovered && !isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(store.isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.09))
                        }
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(store.adaptiveTheme.activeTabBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(store.adaptiveTheme.activeTabStroke, lineWidth: 0.75)
                                )
                        }
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.hitArea)
        .overlay(alignment: .topTrailing) {
            if isRoomy && isHovered {
                Button(action: onClose) {
                    LeanIcon.x.bold
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 7, height: 7)
                        .foregroundColor(store.adaptiveTheme.tabCloseButtonForeground)
                        .frame(width: 16, height: 16)
                        .background(store.adaptiveTheme.tabCloseButtonHoverBackground, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.hitArea)
                .help("Close Tab (⌘W)")
                .padding(3)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .overlay(alignment: .bottomTrailing) {
            if tab.isPlayingMedia {
                TabMediaIndicatorView(tab: tab, theme: store.adaptiveTheme, compact: true)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(isSelected ? store.adaptiveTheme.activeTabBackground : (store.isDarkMode ? Color(white: 0.16) : Color(white: 0.94)))
                            .shadow(color: Color.black.opacity(0.22), radius: 1, x: 0, y: 0.5)
                    )
                    .padding(3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .help(tab.displayTitle(isSelected: isSelected, showFullTitle: true))
        .onHover { isHovered = $0 }
        .onDrag {
            store.draggingTabID = tab.id
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: TabReorderDropDelegate(targetID: tab.id, store: store) { isDropTarget = $0 }
        )
        .overlay(alignment: .leading) {
            if isDropTarget {
                Capsule()
                    .fill(store.adaptiveTheme.primaryText)
                    .frame(width: 2)
                    .padding(.vertical, 6)
            }
        }
        .contextMenu {
            if tab.isPlayingMedia {
                Button {
                    tab.toggleMute()
                } label: {
                    Label(tab.isMuted ? "Unmute Tab" : "Mute Tab", systemImage: tab.isMuted ? "speaker.wave.2" : "speaker.slash")
                }
                Divider()
            }
            Button {
                store.togglePin(tab: tab)
            } label: {
                Label(tab.isPinned ? "Unpin" : "Pin", systemImage: tab.isPinned ? "pin.slash" : "pin")
            }
            Divider()
            if tab.isSleeping {
                Button("Wake Tab", action: onSelect)
            } else {
                Button("Sleep Tab") { store.sleepTab(tab, notifyOnFailure: true) }
                    .disabled(isSelected)
            }
            Button("Close Tab", action: onClose)
            Divider()
            Button("Reload") { tab.reload() }
            if tab.canGoBack {
                Button("Back") { tab.goBack() }
            }
            if tab.canGoForward {
                Button("Forward") { tab.goForward() }
            }
            Divider()
            Button("Duplicate Tab") {
                if let url = tab.url {
                    _ = store.newTab(url: url)
                } else {
                    _ = store.newTab()
                }
            }
        }
    }
}

// MARK: - Sidebar Traffic Lights
private struct SidebarTrafficLights: View {
    @ObservedObject var store: LeanStore
    @State private var isHoveringAll = false
    @State private var isWindowActive = true

    var body: some View {
        HStack(spacing: 8) {
            // 1. Close Button
            TrafficLightButton(
                color: Color(red: 255/255, green: 95/255, blue: 87/255),
                strokeColor: Color(red: 224/255, green: 68/255, blue: 62/255, opacity: 0.9),
                symbol: .x,
                symbolSize: 7.5,
                isHoveringGroup: isHoveringAll,
                isActive: isWindowActive,
                isDark: store.adaptiveTheme.effectiveIsDark
            ) {
                if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
                    window.performClose(nil)
                }
            }

            // 2. Miniaturize Button
            TrafficLightButton(
                color: Color(red: 255/255, green: 189/255, blue: 46/255),
                strokeColor: Color(red: 222/255, green: 161/255, blue: 35/255, opacity: 0.9),
                symbol: .minus,
                symbolSize: 8.0,
                isHoveringGroup: isHoveringAll,
                isActive: isWindowActive,
                isDark: store.adaptiveTheme.effectiveIsDark
            ) {
                if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
                    window.miniaturize(nil)
                }
            }

            // 3. Zoom / Fullscreen Button
            TrafficLightButton(
                color: Color(red: 39/255, green: 201/255, blue: 63/255),
                strokeColor: Color(red: 26/255, green: 171/255, blue: 41/255, opacity: 0.9),
                symbol: .arrowsOutSimple,
                symbolSize: 6.5,
                isHoveringGroup: isHoveringAll,
                isActive: isWindowActive,
                isDark: store.adaptiveTheme.effectiveIsDark
            ) {
                if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
                    window.toggleFullScreen(nil)
                }
            }
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHoveringAll = hovering
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isWindowActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            isWindowActive = false
        }
    }
}

private struct TrafficLightButton: View {
    let color: Color
    let strokeColor: Color
    let symbol: LeanIcon
    let symbolSize: CGFloat
    let isHoveringGroup: Bool
    let isActive: Bool
    let isDark: Bool
    let action: () -> Void

    @State private var isPressed = false

    static let diameter: CGFloat = 14.5
    /// Glyph sizes below were tuned for a 13.5pt button.
    static let symbolScale: CGFloat = diameter / 13.5

    private var effectiveFill: Color {
        guard isActive else {
            return isDark ? Color(white: 0.3) : Color(white: 0.8)
        }
        return color
    }

    private var effectiveStroke: Color {
        guard isActive else {
            return isDark ? Color(white: 0.24) : Color(white: 0.72)
        }
        return strokeColor
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(effectiveFill)
                    .frame(width: Self.diameter, height: Self.diameter)
                    .overlay(
                        Circle()
                            .stroke(effectiveStroke, lineWidth: 0.5)
                    )

                if isHoveringGroup && isActive {
                    symbol.bold
                        .aspectRatio(contentMode: .fit)
                        .frame(width: symbolSize * Self.symbolScale, height: symbolSize * Self.symbolScale)
                        .foregroundColor(Color.black.opacity(0.68))
                }
            }
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(.hitArea)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Window Drag Bridge (shared with TopBarView: empty chrome areas
// fall through to this view so the window stays draggable without the
// window-wide isMovableByWindowBackground behavior that steals button clicks)
struct WindowDragView: NSViewRepresentable {
    var onHover: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> DragNSView {
        DragNSView(onHover: onHover)
    }

    func updateNSView(_ nsView: DragNSView, context: Context) {
        nsView.onHover = onHover
    }

    class DragNSView: NSView {
        var onHover: ((Bool) -> Void)?

        init(onHover: ((Bool) -> Void)?) {
            self.onHover = onHover
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }

        /// This view moves the window itself (below); AppKit must not also.
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else if let window {
                // Tabs make the window unmovable while hovered
                // (WindowDragZones); this press is the one that moves it.
                window.isMovable = true
                window.performDrag(with: event)
            }
        }
    }
}

