import SwiftUI
import WebKit

struct LeanView: View {
    @ObservedObject var store: LeanStore
    @ObservedObject var updater: AppUpdater
    @State private var findQuery = ""
    @State private var hasSetupKeyMonitor = false

    @State private var isZenTopBarRevealed = false
    @State private var hideTopBarWorkItem: DispatchWorkItem?

    @State private var isZenSidebarRevealed = false
    @State private var hideSidebarWorkItem: DispatchWorkItem?
    @State private var isMouseOverSidebar = false

    private var isTopBarVisible: Bool {
        // Popovers must keep the top bar visible
        if store.isQuickSettingsPresented || store.isDownloadsPresented {
            return true
        }
        if !store.enableZenMode {
            return true
        }
        return isZenTopBarRevealed
    }

    private var isSidebarEffectivelyVisible: Bool {
        guard store.tabLayout == .sidebar else { return false }
        // Popovers must keep the sidebar visible
        if store.isQuickSettingsPresented || store.isDownloadsPresented {
            return true
        }
        // If sidebar is pinned (!isSidebarCollapsed), it is ALWAYS visible and expanded (auto-hide disabled)
        if !store.isSidebarCollapsed {
            return true
        }
        // When auto-hide is enabled (isSidebarCollapsed == true), visibility follows hover reveal
        return isZenSidebarRevealed
    }

    private func setZenHoverState(isHoveringTop: Bool) {
        if isHoveringTop {
            hideTopBarWorkItem?.cancel()
            hideTopBarWorkItem = nil
            if !isZenTopBarRevealed {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isZenTopBarRevealed = true
                }
            }
        } else {
            // Never hide while quick settings or downloads popover is open
            if store.isQuickSettingsPresented || store.isDownloadsPresented {
                hideTopBarWorkItem?.cancel()
                hideTopBarWorkItem = nil
                return
            }
            hideTopBarWorkItem?.cancel()
            let item = DispatchWorkItem {
                guard !store.isQuickSettingsPresented && !store.isDownloadsPresented else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isZenTopBarRevealed = false
                }
            }
            hideTopBarWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
        }
    }

    private func setSidebarHoverState(isHovering: Bool) {
        // If sidebar is pinned, auto-hide is completely disabled - do nothing
        guard store.isSidebarCollapsed else {
            hideSidebarWorkItem?.cancel()
            hideSidebarWorkItem = nil
            return
        }

        if isHovering {
            hideSidebarWorkItem?.cancel()
            hideSidebarWorkItem = nil
            if !isZenSidebarRevealed {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isZenSidebarRevealed = true
                }
            }
        } else {
            // Never hide while quick settings or downloads popover is open
            if store.isQuickSettingsPresented || store.isDownloadsPresented {
                hideSidebarWorkItem?.cancel()
                hideSidebarWorkItem = nil
                return
            }
            hideSidebarWorkItem?.cancel()
            let item = DispatchWorkItem {
                guard !store.isQuickSettingsPresented && !store.isDownloadsPresented else { return }
                if store.isSidebarCollapsed {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isZenSidebarRevealed = false
                    }
                }
            }
            hideSidebarWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: item)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if store.tabLayout == .sidebar {
                ZStack(alignment: .topLeading) {
                    mainContentCard

                    if isSidebarEffectivelyVisible {
                        sidebarCard
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                            .zIndex(40)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    // Top Bar - In Zen mode, disappears and reveals on hover
                    if isTopBarVisible {
                        TopBarView(store: store)
                            .onHover { hovering in
                                if store.enableZenMode {
                                    setZenHoverState(isHoveringTop: hovering)
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                            .zIndex(20)
                    }

                    mainContentCard
                }
            }

            // Left Sidebar Hover Detection Zone (invisible trigger active at left edge when sidebar is hidden)
            if store.tabLayout == .sidebar && !isSidebarEffectivelyVisible {
                Color.clear
                    .frame(width: 18)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            setSidebarHoverState(isHovering: true)
                        }
                    }
                    .zIndex(50)
            }

            // Top Hover Detection Zone (invisible trigger active at top edge in Zen mode when top bar is hidden)
            if store.enableZenMode && store.tabLayout == .top && !isTopBarVisible {
                Color.clear
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            setZenHoverState(isHoveringTop: true)
                        }
                    }
                    .zIndex(50)
            }
            // Floating Omnibar Overlay (Cmd+T / Cmd+L / Active Tab Pill Click)
            if store.isFloatingOmnibarVisible {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.0001)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            store.dismissFloatingOmnibar()
                        }

                    VStack(spacing: 0) {
                        Spacer().frame(height: 72)
                        OmnibarView(store: store, isFloating: true)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                    removal: .opacity
                ))
                .animation(.easeOut(duration: 0.12), value: store.isFloatingOmnibarVisible)
                .zIndex(150)
            }

            // Bespoke Quick Settings Overlay
            if store.isQuickSettingsPresented {
                ZStack(alignment: store.tabLayout == .sidebar ? .bottomLeading : .topTrailing) {
                    Color.black.opacity(0.0001)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                store.isQuickSettingsPresented = false
                            }
                        }

                    QuickSettingsPopover(store: store)
                        .padding(.top, store.tabLayout == .sidebar ? 0 : ((store.enableWindowBorder ? 34 : 36) + (store.enableWindowBorder ? store.windowBorderWidth : 4)))
                        .padding(.trailing, store.tabLayout == .sidebar ? 0 : ((store.enableWindowBorder ? store.windowBorderWidth : 0) + 12))
                        .padding(.leading, store.tabLayout == .sidebar ? (store.windowBorderWidth + 12) : 0)
                        .padding(.bottom, store.tabLayout == .sidebar ? (store.windowBorderWidth + 46) : 0)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94, anchor: store.tabLayout == .sidebar ? .bottomLeading : .topTrailing).combined(with: .opacity),
                    removal: .scale(scale: 0.96, anchor: store.tabLayout == .sidebar ? .bottomLeading : .topTrailing).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.22, dampingFraction: 0.82), value: store.isQuickSettingsPresented)
                .zIndex(190)
            }

            // Bespoke Downloads Overlay
            if store.isDownloadsPresented {
                ZStack(alignment: store.tabLayout == .sidebar ? .bottomLeading : .topTrailing) {
                    Color.black.opacity(0.0001)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                store.isDownloadsPresented = false
                            }
                        }

                    DownloadsPopover(store: store)
                        .padding(.top, store.tabLayout == .sidebar ? 0 : ((store.enableWindowBorder ? 34 : 36) + (store.enableWindowBorder ? store.windowBorderWidth : 4)))
                        .padding(.trailing, store.tabLayout == .sidebar ? 0 : ((store.enableWindowBorder ? store.windowBorderWidth : 0) + 12))
                        .padding(.leading, store.tabLayout == .sidebar ? (store.windowBorderWidth + 12) : 0)
                        .padding(.bottom, store.tabLayout == .sidebar ? (store.windowBorderWidth + 46) : 0)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94, anchor: store.tabLayout == .sidebar ? .bottomLeading : .topTrailing).combined(with: .opacity),
                    removal: .scale(scale: 0.96, anchor: store.tabLayout == .sidebar ? .bottomLeading : .topTrailing).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.22, dampingFraction: 0.82), value: store.isDownloadsPresented)
                .zIndex(190)
            }

            // Ctrl+Tab Thumbnail Switcher Overlay
            if store.isTabSwitcherVisible {
                TabSwitcherView(store: store)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    ))
                    .animation(.spring(response: 0.22, dampingFraction: 0.84), value: store.isTabSwitcherVisible)
                    .zIndex(100)
            }

            // When inline URL bar is being edited, clicking anywhere in the content area collapses it
            if store.isInlineURLEditing {
                Color.black.opacity(0.0001)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        store.dismissInlineURLEditing()
                    }
                    .zIndex(15)
            }
        }
        .ignoresSafeArea(.all)
        .background(
            store.enableWindowBorder
                ? AnyView(store.effectiveZenColor.ignoresSafeArea())
                : AnyView(store.themeColors.windowBackground.ignoresSafeArea())
        )
        .background(WindowConfigurator(store: store, isTopBarVisible: isTopBarVisible, isSidebarVisible: isSidebarEffectivelyVisible))
        .preferredColorScheme(store.colorScheme)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isTopBarVisible)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: isSidebarEffectivelyVisible)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: store.isSidebarCollapsed)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: cardLeadingPadding)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: store.tabLayout)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: store.enableZenMode)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: store.enableWindowBorder)
        .animation(.easeInOut(duration: 0.2), value: store.effectiveZenColor)
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: store.windowBorderWidth)
        .onAppear {
            setupKeyMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddress)) { _ in
            if store.selectedTab?.url != nil {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    store.isInlineURLEditing = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if store.isInlineURLEditing {
                store.dismissInlineURLEditing()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if store.isInlineURLEditing {
                store.dismissInlineURLEditing()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFind)) { _ in
            store.showsFindBar = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            store.openSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                if store.isSidebarCollapsed {
                    // Auto-hide enabled: if mouse is not over sidebar, hide it immediately
                    if !isMouseOverSidebar {
                        isZenSidebarRevealed = false
                    }
                } else {
                    // Pinned / Always Expanded
                    isZenSidebarRevealed = true
                }
            }
        }
        .onChange(of: store.isQuickSettingsPresented) { _, presented in
            if !presented {
                if store.enableZenMode && store.tabLayout == .top {
                    setZenHoverState(isHoveringTop: false)
                }
                if store.isSidebarCollapsed && store.tabLayout == .sidebar && !isMouseOverSidebar {
                    setSidebarHoverState(isHovering: false)
                }
            }
        }
        .onChange(of: store.isDownloadsPresented) { _, presented in
            if !presented {
                if store.enableZenMode && store.tabLayout == .top {
                    setZenHoverState(isHoveringTop: false)
                }
                if store.isSidebarCollapsed && store.tabLayout == .sidebar && !isMouseOverSidebar {
                    setSidebarHoverState(isHovering: false)
                }
            }
        }
    }

    // MARK: - Framed Sidebar Card
    private var sidebarCard: some View {
        SidebarView(store: store)
            .clipShape(RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous)
                    .stroke(store.adaptiveTheme.webCardStroke, lineWidth: 1)
            )
            .shadow(
                color: store.adaptiveTheme.webCardShadow,
                radius: 18,
                x: 6,
                y: 2
            )
            .padding(.top, store.windowBorderWidth)
            .padding(.bottom, store.windowBorderWidth)
            .padding(.leading, store.windowBorderWidth)
            .onHover { hovering in
                isMouseOverSidebar = hovering
                if store.isSidebarCollapsed {
                    setSidebarHoverState(isHovering: hovering)
                }
            }
    }

    // MARK: - Main Content Card & Spacing
    private var cardTopPadding: CGFloat {
        if !store.enableWindowBorder { return 0 }
        if store.tabLayout == .sidebar {
            return store.windowBorderWidth
        }
        return isTopBarVisible ? 2 : store.windowBorderWidth
    }

    private var cardBottomPadding: CGFloat {
        store.enableWindowBorder ? store.windowBorderWidth : 0
    }

    private var isCurrentTabWebPage: Bool {
        store.selectedTab?.url != nil || store.selectedTab?.isSettingsPage == true
    }

    private var cardLeadingPadding: CGFloat {
        let basePadding = store.enableWindowBorder ? store.windowBorderWidth : 0
        if store.tabLayout == .sidebar && isSidebarEffectivelyVisible && !store.isSidebarCollapsed && isCurrentTabWebPage {
            let gap = store.enableWindowBorder ? store.windowBorderWidth : 8
            return basePadding + 256 + gap
        }
        return basePadding
    }

    private var cardTrailingPadding: CGFloat {
        store.enableWindowBorder ? store.windowBorderWidth : 0
    }

    private var mainContentCard: some View {
        ZStack {
            (store.enableWindowBorder ? Color.clear : store.themeColors.windowBackground)
                .ignoresSafeArea()

            if let tab = store.selectedTab {
                if tab.isSettingsPage {
                    SettingsView(store: store, updater: updater)
                        .id(tab.id)
                        .clipShape(RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous)
                                .stroke(store.adaptiveTheme.webCardStroke, lineWidth: 1)
                        )
                        .shadow(
                            color: store.adaptiveTheme.webCardShadow,
                            radius: store.adaptiveTheme.webCardShadowRadius,
                            x: 0,
                            y: store.adaptiveTheme.isFrameLight ? 2 : 3
                        )
                        .padding(.leading, cardLeadingPadding)
                        .padding(.trailing, cardTrailingPadding)
                        .padding(.bottom, cardBottomPadding)
                        .padding(.top, cardTopPadding)
                } else if tab.url != nil {
                    // Web Page Loaded — engine slot. Shell chrome is identical
                    // for both engines; only this content view branches.
                    // WebKit renders WKWebView. CEF tabs render the real
                    // CEFEngineView once the framework lands (see docs/CEF.md);
                    // until then they render an in-content notice.
                    ZStack(alignment: .topTrailing) {
                        if tab.engineKind == .cef && !CEFIntegration.isAvailable() {
                            CEFUnavailableView(store: store)
                                .id(tab.id)
                        } else {
                            WebView(tab: tab)
                                .id(tab.id)
                        }

                        if store.showsFindBar {
                            floatingFindBar
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous)
                            .stroke(store.adaptiveTheme.webCardStroke, lineWidth: 1)
                    )
                    .shadow(
                        color: store.adaptiveTheme.webCardShadow,
                        radius: store.adaptiveTheme.webCardShadowRadius,
                        x: 0,
                        y: store.adaptiveTheme.isFrameLight ? 2 : 3
                    )
                    .padding(.leading, cardLeadingPadding)
                    .padding(.trailing, cardTrailingPadding)
                    .padding(.bottom, cardBottomPadding)
                    .padding(.top, cardTopPadding)
                } else {
                    // New Tab Empty Canvas
                    ZStack {
                        store.themeColors.windowBackground
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if store.isNewTabOmnibarFloating {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        store.isNewTabOmnibarFloating = false
                                    }
                                }
                            }

                        VStack(spacing: 0) {
                            if store.isNewTabOmnibarFloating {
                                Spacer().frame(height: 80)
                            } else {
                                Spacer()
                            }

                            OmnibarView(store: store, isFloating: false)

                            Spacer()
                            if !store.isNewTabOmnibarFloating {
                                Spacer()
                            }
                        }
                        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: store.isNewTabOmnibarFloating)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous)
                            .stroke(store.adaptiveTheme.webCardStroke, lineWidth: 1)
                    )
                    .shadow(
                        color: store.adaptiveTheme.webCardShadow,
                        radius: store.adaptiveTheme.webCardShadowRadius,
                        x: 0,
                        y: store.adaptiveTheme.isFrameLight ? 2 : 3
                    )
                    .padding(.leading, cardLeadingPadding)
                    .padding(.trailing, cardTrailingPadding)
                    .padding(.bottom, cardBottomPadding)
                    .padding(.top, cardTopPadding)
                }
            }
        }
    }

    private func setupKeyMonitor() {
        guard !hasSetupKeyMonitor else { return }
        hasSetupKeyMonitor = true

        // Monitor mouse clicks when quick settings, inline URL bar, or floating omnibar is open:
        // Only clicking outside the active region collapses / closes it!
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            guard let window = event.window ?? NSApp.keyWindow else { return event }

            // Convert AppKit window coordinates (origin bottom-left) to SwiftUI global coordinates (origin top-left)
            let windowHeight = window.contentView?.frame.height ?? window.frame.height
            let clickLocation = event.locationInWindow
            let swiftUIPoint = CGPoint(x: clickLocation.x, y: windowHeight - clickLocation.y)

            // When Quick Settings popover is open, dismiss when clicking outside its bounds (and the gear button)
            if store.isQuickSettingsPresented {
                let popoverFrame = store.quickSettingsPopoverFrame
                let submenuFrame = store.quickSettingsSubmenuFrame
                let buttonFrame = store.settingsButtonFrame
                let isInsidePopover = popoverFrame.width > 0 && popoverFrame.contains(swiftUIPoint)
                let isInsideSubmenu = submenuFrame.width > 0 && submenuFrame.contains(swiftUIPoint)
                let isInsideButton = buttonFrame.width > 0 && buttonFrame.contains(swiftUIPoint)
                if !isInsidePopover && !isInsideSubmenu && !isInsideButton {
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                        store.isQuickSettingsPresented = false
                    }
                }
            }

            // When Downloads popover is open, dismiss when clicking outside its bounds (and the button)
            if store.isDownloadsPresented {
                let popoverFrame = store.downloadsPopoverFrame
                let buttonFrame = store.downloadsButtonFrame
                let isInsidePopover = popoverFrame.width > 0 && popoverFrame.contains(swiftUIPoint)
                let isInsideButton = buttonFrame.width > 0 && buttonFrame.contains(swiftUIPoint)
                if !isInsidePopover && !isInsideButton {
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                        store.isDownloadsPresented = false
                    }
                }
            }

            // When inline URL bar is being edited, dismiss when clicking outside its bounds (and dropdown)
            if store.isInlineURLEditing {
                let barFrame = store.inlineURLBarFrame.insetBy(dx: -4, dy: -4)
                let suggFrame = store.inlineSuggestionsFrame.insetBy(dx: -4, dy: -4)
                let isInsideBar = store.inlineURLBarFrame.width > 0 && barFrame.contains(swiftUIPoint)
                let isInsideSugg = store.inlineSuggestionsFrame.width > 0 && suggFrame.contains(swiftUIPoint)

                if !isInsideBar && !isInsideSugg {
                    store.dismissInlineURLEditing()
                }
                return event
            }

            guard store.isFloatingOmnibarVisible else { return event }

            let paletteFrame = store.floatingPaletteFrame
            let effectivePaletteFrame: CGRect
            if paletteFrame.width > 0 && paletteFrame.height > 0 {
                effectivePaletteFrame = paletteFrame
            } else {
                let windowWidth = window.contentView?.frame.width ?? window.frame.width
                let x = max(0, (windowWidth - 580) / 2)
                effectivePaletteFrame = CGRect(x: x, y: 72, width: 580, height: 350)
            }

            if effectivePaletteFrame.contains(swiftUIPoint) {
                return event
            } else {
                store.dismissFloatingOmnibar()
                return nil
            }
        }

        // Monitor keyDown for registered custom shortcuts and Escape
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Intercept Escape (keyCode 53) to close quick settings, inline url bar, floating omnibar, new tab omnibar, or tab switcher
            if event.keyCode == 53 {
                if store.isDownloadsPresented {
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                        store.isDownloadsPresented = false
                    }
                    return nil
                }
                if store.isQuickSettingsPresented {
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                        store.isQuickSettingsPresented = false
                    }
                    return nil
                }
                if store.isInlineURLEditing {
                    store.dismissInlineURLEditing()
                    return nil
                }
                if store.isFloatingOmnibarVisible {
                    store.dismissFloatingOmnibar()
                    return nil
                }
                if store.isNewTabOmnibarFloating {
                    store.dismissNewTabOmnibar()
                    return nil
                }
                if store.isTabSwitcherVisible {
                    store.cancelTabSwitcher()
                    return nil
                }
            }

            // Check custom shortcuts
            for action in ShortcutAction.allCases {
                if action == .dismiss || action == .stopLoading {
                    continue // Handled above or conditionally
                }
                let combo = store.shortcut(for: action)
                if combo.matches(event: event) {
                    action.performAction(in: store)
                    return nil
                }
            }

            return event
        }

        // Monitor flagsChanged to detect release of Control key
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            if store.isTabSwitcherVisible && !event.modifierFlags.contains(.control) {
                store.commitTabSwitcher()
            }
            return event
        }
    }

    private var floatingFindBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(store.themeColors.secondaryText)

            TextField("Find on page", text: $findQuery)
                .textFieldStyle(.plain)
                .font(store.leanUIFont.font(size: 13))
                .foregroundColor(store.themeColors.omnibarText)
                .frame(width: 150)
                .onSubmit { store.selectedTab?.find(findQuery) }

            Button {
                store.selectedTab?.find(findQuery)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(store.themeColors.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Find Next")

            Button {
                store.showsFindBar = false
                findQuery = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(store.themeColors.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            store.themeColors.omnibarBackground,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(store.themeColors.omnibarBorder, lineWidth: 1)
        )
        .shadow(
            color: store.isDarkMode ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
            radius: 8, x: 0, y: 2
        )
        .padding(.top, 10)
        .padding(.trailing, 14)
    }
}

private struct WebView: NSViewRepresentable {
    @ObservedObject var tab: LeanTab

    func makeNSView(context: Context) -> WKWebView {
        tab.webView.wantsLayer = true
        tab.webView.layer?.drawsAsynchronously = true
        return tab.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.wantsLayer = true
        nsView.layer?.drawsAsynchronously = true
    }
}

/// In-content notice for CEF tabs when the framework is not bundled.
/// Lives inside the web content card only — top bar, sidebar, omnibar,
/// and settings chrome are untouched.
private struct CEFUnavailableView: View {
    @ObservedObject var store: LeanStore

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(store.themeColors.secondaryText)
            Text("Chromium engine not installed")
                .font(store.headingFont(size: 14))
                .foregroundColor(store.themeColors.omnibarText)
            Text("This tab asked for CEF, but the Chromium framework isn't bundled with this build. New tabs keep using WebKit until CEF lands — see docs/CEF.md.")
                .font(store.bodyFont(size: 12))
                .foregroundColor(store.themeColors.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                store.engineKind = .webKit
            } label: {
                Text("Use WebKit for new tabs")
                    .font(store.bodyFont(size: 12))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        store.themeColors.omnibarBackground,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(store.themeColors.windowBackground)
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    @ObservedObject var store: LeanStore
    let isTopBarVisible: Bool
    let isSidebarVisible: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(view: nsView)
        }
    }

    private func configure(view: NSView) {
        guard let window = view.window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = store.enableWindowBorder
            ? NSColor(store.effectiveZenColor)
            : (store.isDarkMode ? NSColor.black : NSColor.white)
        window.appearance = store.enableWindowBorder
            ? (store.adaptiveTheme.isFrameLight ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua))
            : (store.isDarkMode ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua))

        if store.tabLayout == .sidebar {
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        } else {
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = false

            let targetAlpha: CGFloat = (!store.enableZenMode || isTopBarVisible || isSidebarVisible) ? 1.0 : 0.0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.standardWindowButton(.closeButton)?.animator().alphaValue = targetAlpha
                window.standardWindowButton(.miniaturizeButton)?.animator().alphaValue = targetAlpha
                window.standardWindowButton(.zoomButton)?.animator().alphaValue = targetAlpha
            }
        }
    }
}

extension Notification.Name {
    static let focusAddress = Notification.Name("Lean.focusAddress")
    static let showFind = Notification.Name("Lean.showFind")
    static let showSettings = Notification.Name("Lean.showSettings")
    static let toggleSidebar = Notification.Name("Lean.toggleSidebar")
}
