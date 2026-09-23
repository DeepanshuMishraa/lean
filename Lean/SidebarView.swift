import AppKit
import SwiftUI

// MARK: - Sidebar View for Vertical Tabs
struct SidebarView: View {
    @ObservedObject var store: LeanStore

    private var sidebarBackground: Color {
        store.adaptiveTheme.isBorderEnabled
            ? store.adaptiveTheme.activeTabBackground
            : (store.isDarkMode ? Color(red: 32/255, green: 33/255, blue: 38/255) : Color(white: 0.96))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Header Row: Custom Titlebar with Traffic Lights + Navigation Controls
            HStack(spacing: 0) {
                SidebarTrafficLights(store: store)
                    .padding(.leading, 12)

                Spacer().frame(width: 12)

                InteractiveIconButton(
                    icon: .sidebar,
                    helpText: store.isSidebarCollapsed ? "Pin Sidebar (Always Expanded) (⌘S)" : "Enable Auto-hide (⌘S)",
                    size: 24,
                    iconSize: 12,
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

                Spacer().frame(width: 4)

                InteractiveIconButton(
                    icon: .arrowLeft,
                    helpText: "Back (⌘[)",
                    size: 24,
                    iconSize: 12,
                    color: store.selectedTab?.canGoBack == true ? store.adaptiveTheme.primaryText : store.adaptiveTheme.disabledIconText,
                    hoverColor: store.adaptiveTheme.primaryText,
                    disabledColor: store.adaptiveTheme.disabledIconText,
                    hoverBackground: store.adaptiveTheme.iconHoverBackground,
                    pressedBackground: store.adaptiveTheme.iconPressedBackground,
                    isDark: store.adaptiveTheme.effectiveIsDark,
                    isEnabled: store.selectedTab?.canGoBack == true
                ) {
                    store.selectedTab?.goBack()
                }

                Spacer().frame(width: 4)

                InteractiveIconButton(
                    icon: .arrowRight,
                    helpText: "Forward (⌘])",
                    size: 24,
                    iconSize: 12,
                    color: store.selectedTab?.canGoForward == true ? store.adaptiveTheme.primaryText : store.adaptiveTheme.disabledIconText,
                    hoverColor: store.adaptiveTheme.primaryText,
                    disabledColor: store.adaptiveTheme.disabledIconText,
                    hoverBackground: store.adaptiveTheme.iconHoverBackground,
                    pressedBackground: store.adaptiveTheme.iconPressedBackground,
                    isDark: store.adaptiveTheme.effectiveIsDark,
                    isEnabled: store.selectedTab?.canGoForward == true
                ) {
                    store.selectedTab?.goForward()
                }

                Spacer().frame(width: 4)

                if store.selectedTab?.isLoading == true {
                    InteractiveIconButton(
                        icon: .x,
                        helpText: "Stop Loading (Esc)",
                        size: 24,
                        iconSize: 12,
                        color: store.adaptiveTheme.primaryText,
                        hoverColor: store.adaptiveTheme.primaryText,
                        hoverBackground: store.adaptiveTheme.iconHoverBackground,
                        pressedBackground: store.adaptiveTheme.iconPressedBackground,
                        isDark: store.adaptiveTheme.effectiveIsDark,
                        isEnabled: true
                    ) {
                        store.selectedTab?.stop()
                    }
                } else {
                    InteractiveIconButton(
                        icon: .arrowClockwise,
                        helpText: "Reload (⌘R)",
                        size: 24,
                        iconSize: 12,
                        color: store.selectedTab?.url != nil ? store.adaptiveTheme.primaryText : store.adaptiveTheme.disabledIconText,
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

                Spacer(minLength: 0)
                    .background(WindowDragView())
                WindowDragView()
                    .frame(width: 8)
            }
            .frame(height: store.scaled(36))
            .padding(.top, store.scaled(4))
            .padding(.trailing, 8)

            // 2. Full-Width Interactive Omnibar / Address Field
            SidebarAddressBar(store: store)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 12)
                .zIndex(10)

            // 3. Section Title Row with + New Tab Icon
            HStack(spacing: 6) {
                Text("Tabs")
                    .font(store.headingFont(size: 11.5))
                    .foregroundColor(store.adaptiveTheme.secondaryText)
                    .textCase(.uppercase)
                    .kerning(0.5)

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

            // 5. Vertical Tab Strip
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(store.tabs) { tab in
                        SidebarTabItem(
                            tab: tab,
                            isSelected: tab.id == store.selectedID,
                            store: store,
                            onSelect: { handleTabSelection(tab) },
                            onClose: { store.close(tab) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            Spacer(minLength: 0)

            // 6. Bottom Footer Row: Downloads, Theme toggle, Settings, New Tab
            HStack(spacing: 6) {
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
        .background(sidebarBackground)
    }

    private func handleTabSelection(_ tab: LeanTab) {
        if tab.id == store.selectedID {
            NotificationCenter.default.post(name: .focusAddress, object: nil)
        } else {
            store.switchToTab(id: tab.id)
        }
    }
}

// MARK: - Sidebar Address / Omnibar Field
private struct SidebarAddressBar: View {
    @ObservedObject var store: LeanStore
    @FocusState private var isFocused: Bool
    @State private var text = ""
    @State private var selectedIndex = 0
    @State private var didCopyLink = false

    private var openTabsForSuggestions: [(id: UUID, title: String, url: URL)] {
        store.tabs.compactMap { t in
            guard let url = t.url, t.id != store.selectedID else { return nil }
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
    }

    private var barBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(store.adaptiveTheme.inlineURLBarBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isFocused
                            ? store.adaptiveTheme.activeTabStroke
                            : store.adaptiveTheme.inlineURLBarStroke,
                        lineWidth: 1
                    )
            )
    }

    @ViewBuilder
    private var suggestionsOverlay: some View {
        if isFocused && !suggestions.isEmpty {
            VStack(spacing: 2) {
                ForEach(Array(suggestions.prefix(6).enumerated()), id: \.element.id) { index, match in
                    HStack(spacing: 8) {
                        (match.isSearch ? Ph.magnifyingGlass.fill : (match.isSwitchToTab ? Ph.arrowCircleRight.fill : Ph.browser.fill))
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
                            .font(store.bodyFont(size: 10.5))
                            .foregroundColor(store.adaptiveTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        index == selectedIndex
                            ? store.adaptiveTheme.iconHoverBackground
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        execute(match)
                    }
                }
            }
            .padding(6)
            .background(
                store.adaptiveTheme.dropdownBackground,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(store.adaptiveTheme.dropdownStroke, lineWidth: 0.75)
            )
            .shadow(color: store.adaptiveTheme.dropdownShadow, radius: 12, x: 0, y: 5)
            .padding(.top, 40)
            .zIndex(100)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Ph.magnifyingGlass.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .foregroundColor(store.adaptiveTheme.secondaryText)

            addressField

            Spacer(minLength: 4)

            if isFocused && !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Ph.xCircle.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                    (didCopyLink ? Ph.check.bold : Ph.copy.fill)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundColor(didCopyLink ? Color.green : store.adaptiveTheme.secondaryText)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        .overlay(alignment: .top) {
            suggestionsOverlay
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
    @ObservedObject var store: LeanStore
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

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
                .animation(.easeInOut(duration: 0.2), value: tab.isLoading)

                Text(tab.displayTitle(isSelected: isSelected, showFullTitle: true))
                    .font(store.tabTitleFont(size: 13))
                    .foregroundColor(tabItemForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)
                // Always reserve close-button width so hover doesn't push text.
                Color.clear.frame(width: 18, height: 18)
            }
            .padding(.horizontal, store.scaled(10))
            .frame(height: store.scaled(36))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? store.adaptiveTheme.inactiveTabHoverBackground
                        : (isHovered ? store.adaptiveTheme.inactiveTabBackground : Color.clear)
                )
                .overlay(
                    isSelected
                        ? RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(store.adaptiveTheme.activeTabStroke, lineWidth: 1)
                        : nil
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .overlay(alignment: .trailing) {
            if showsClose {
                Button(action: onClose) {
                    Ph.x.bold
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
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Close Tab (⌘W)")
                .padding(.trailing, 8)
            }
        }
        .contextMenu {
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
                symbolSize: 6,
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
                symbolSize: 6.5,
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
                symbolSize: 5.5,
                isHoveringGroup: isHoveringAll,
                isActive: isWindowActive,
                isDark: store.adaptiveTheme.effectiveIsDark
            ) {
                if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
                    window.toggleFullScreen(nil)
                }
            }
        }
        .frame(height: 16)
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
    let symbol: Ph
    let symbolSize: CGFloat
    let isHoveringGroup: Bool
    let isActive: Bool
    let isDark: Bool
    let action: () -> Void

    @State private var isPressed = false

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
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(effectiveStroke, lineWidth: 0.5)
                    )

                if isHoveringGroup && isActive {
                    symbol.bold
                        .aspectRatio(contentMode: .fit)
                        .frame(width: symbolSize, height: symbolSize)
                        .foregroundColor(Color.black.opacity(0.65))
                }
            }
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(.plain)
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

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

