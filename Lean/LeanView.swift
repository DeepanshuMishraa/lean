import SwiftUI
import WebKit

private let topRowDigitByKeyCode: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

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
        if store.isQuickSettingsPresented || store.isDownloadsPresented || store.isExtensionsPresented {
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
        if store.isQuickSettingsPresented || store.isDownloadsPresented || store.isExtensionsPresented {
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
            // Never hide while quick settings, downloads, or extensions popover is open
            if store.isQuickSettingsPresented || store.isDownloadsPresented || store.isExtensionsPresented {
                hideTopBarWorkItem?.cancel()
                hideTopBarWorkItem = nil
                return
            }
            hideTopBarWorkItem?.cancel()
            let item = DispatchWorkItem {
                guard !store.isQuickSettingsPresented && !store.isDownloadsPresented && !store.isExtensionsPresented else { return }
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
            // Never hide while quick settings, downloads, or extensions popover is open
            if store.isQuickSettingsPresented || store.isDownloadsPresented || store.isExtensionsPresented {
                hideSidebarWorkItem?.cancel()
                hideSidebarWorkItem = nil
                return
            }
            hideSidebarWorkItem?.cancel()
            let item = DispatchWorkItem {
                guard !store.isQuickSettingsPresented && !store.isDownloadsPresented && !store.isExtensionsPresented else { return }
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
                WindowDragView { hovering in
                    if hovering {
                        setSidebarHoverState(isHovering: true)
                    }
                }
                .frame(width: 18)
                .frame(maxHeight: .infinity)
                .zIndex(50)
            }

            // Top Hover Detection Zone (invisible trigger active at top edge in Zen mode when top bar is hidden)
            if store.enableZenMode && store.tabLayout == .top && !isTopBarVisible {
                WindowDragView { hovering in
                    if hovering {
                        setZenHoverState(isHoveringTop: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .zIndex(50)
            }
            // Floating Omnibar Overlay (Cmd+T / Cmd+L / Active Tab Pill Click)
            // NOTE: no full-screen tap catcher here on purpose. Outside-click
            // dismiss is owned by the NSEvent mouse monitor below, which does
            // not swallow the click, so the underlying toolbar button fires
            // on the very first press.
            if store.isFloatingOmnibarVisible {
                VStack(spacing: 0) {
                    Spacer().frame(height: store.scaled(72))
                    OmnibarView(store: store, isFloating: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    QuickSettingsPopover(store: store)
                        .padding(.top, store.tabLayout == .sidebar ? 0 : store.scaled(store.enableWindowBorder ? 34 : 36) + (store.enableWindowBorder ? store.windowBorderWidth : store.scaled(4)))
                        .padding(.trailing, store.tabLayout == .sidebar ? 0 : ((store.enableWindowBorder ? store.windowBorderWidth : 0) + 12))
                        .padding(.leading, store.tabLayout == .sidebar ? (store.windowBorderWidth + 12) : 0)
                        .padding(.bottom, store.tabLayout == .sidebar ? (store.windowBorderWidth + 46) : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: store.tabLayout == .sidebar ? .bottomLeading : .topTrailing)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity
                ))
                .animation(.easeOut(duration: 0.12), value: store.isQuickSettingsPresented)
                .zIndex(190)
            }

            // Bespoke Downloads Overlay
            if store.isDownloadsPresented {
                ZStack(alignment: store.tabLayout == .sidebar ? .bottomLeading : .topTrailing) {
                    DownloadsPopover(store: store)
                        .padding(.top, store.tabLayout == .sidebar ? 0 : store.scaled(store.enableWindowBorder ? 34 : 36) + (store.enableWindowBorder ? store.windowBorderWidth : store.scaled(4)))
                        .padding(.trailing, store.tabLayout == .sidebar ? 0 : ((store.enableWindowBorder ? store.windowBorderWidth : 0) + 12))
                        .padding(.leading, store.tabLayout == .sidebar ? (store.windowBorderWidth + 12) : 0)
                        .padding(.bottom, store.tabLayout == .sidebar ? (store.windowBorderWidth + 46) : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: store.tabLayout == .sidebar ? .bottomLeading : .topTrailing)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity
                ))
                .animation(.easeOut(duration: 0.12), value: store.isDownloadsPresented)
                .zIndex(190)
            }

            // Bespoke Extensions Overlay
            if store.isExtensionsPresented {
                ZStack(alignment: store.tabLayout == .sidebar ? .bottomLeading : .topTrailing) {
                    ExtensionsPopover(store: store)
                        .padding(.top, store.tabLayout == .sidebar ? 0 : store.scaled(store.enableWindowBorder ? 34 : 36) + (store.enableWindowBorder ? store.windowBorderWidth : store.scaled(4)))
                        .padding(.trailing, store.tabLayout == .sidebar ? 0 : ((store.enableWindowBorder ? store.windowBorderWidth : 0) + 12))
                        .padding(.leading, store.tabLayout == .sidebar ? (store.windowBorderWidth + 12) : 0)
                        .padding(.bottom, store.tabLayout == .sidebar ? (store.windowBorderWidth + 46) : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: store.tabLayout == .sidebar ? .bottomLeading : .topTrailing)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity
                ))
                .animation(.easeOut(duration: 0.12), value: store.isExtensionsPresented)
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

            if let tab = store.selectedTab, tab.isZoomIndicatorVisible {
                ZoomIndicatorView(store: store, zoom: tab.pageZoom)
                    .padding(.top, zoomIndicatorTopPadding)
                    .padding(.trailing, zoomIndicatorTrailingPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.94))
                                .combined(with: .offset(y: -4)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.96))
                                .combined(with: .offset(y: -2))
                        )
                    )
                    .animation(.spring(response: 0.22, dampingFraction: 0.82), value: tab.isZoomIndicatorVisible)
                    .animation(.spring(response: 0.20, dampingFraction: 0.8), value: tab.pageZoom)
                    .zIndex(120)
                    .allowsHitTesting(false)
            }

            // Onboarding Overlay (First launch or manual invocation)
            if store.isOnboardingPresented {
                OnboardingView(store: store)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .scale(scale: 1.02))
                    ))
                    .zIndex(300)
            }

            // Inline URL editing dismiss is owned by the NSEvent mouse monitor
            // below (pass-through, no click swallowing), so no overlay here.
        }
        .environment(\.browserUIScale, store.browserUIScale)
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
        .onChange(of: store.isExtensionsPresented) { _, presented in
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
            || store.selectedTab?.isPageSource == true
    }

    private var cardLeadingPadding: CGFloat {
        let basePadding = store.enableWindowBorder ? store.windowBorderWidth : 0
        if store.tabLayout == .sidebar && isSidebarEffectivelyVisible && !store.isSidebarCollapsed && isCurrentTabWebPage {
            let gap = store.enableWindowBorder ? store.windowBorderWidth : 8
            return basePadding + store.scaled(256) + gap
        }
        return basePadding
    }

    private var cardTrailingPadding: CGFloat {
        store.enableWindowBorder ? store.windowBorderWidth : 0
    }

    private var zoomIndicatorTopPadding: CGFloat {
        if store.tabLayout == .top && isTopBarVisible {
            let topBarHeight = store.scaled(store.enableWindowBorder ? 34 : 36)
            let borderPadding = store.enableWindowBorder ? store.windowBorderWidth : 0
            return topBarHeight + borderPadding + store.scaled(10)
        } else {
            let borderPadding = store.enableWindowBorder ? store.windowBorderWidth : 0
            return borderPadding + store.scaled(12)
        }
    }

    private var zoomIndicatorTrailingPadding: CGFloat {
        let borderPadding = store.enableWindowBorder ? store.windowBorderWidth : 0
        return borderPadding + store.scaled(14)
    }

    private var mainContentCard: some View {
        ZStack {
            (store.enableWindowBorder ? Color.clear : store.themeColors.windowBackground)
                .ignoresSafeArea()

            if let tab = store.selectedTab {
                if tab.isSplit {
                    SplitTabsContainerView(parentTab: tab, store: store)
                        .padding(.leading, cardLeadingPadding)
                        .padding(.trailing, cardTrailingPadding)
                        .padding(.bottom, cardBottomPadding)
                        .padding(.top, cardTopPadding)
                } else if tab.isSettingsPage {
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
                } else if tab.url != nil || tab.isPageSource {
                    // Web Page Loaded
                    ZStack(alignment: .topTrailing) {
                        WebView(tab: tab)
                            .id(tab.id)

                        if store.showsFindBar {
                            floatingFindBar
                        }
                    }
                    .overlay(alignment: .top) {
                        if store.enableZenMode {
                            PageLoadingBar(
                                isLoading: tab.isLoading,
                                progress: tab.loadingProgress,
                                isDark: store.isDarkMode
                            )
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        SavedPasswordSuggestionOverlay(tab: tab, isDark: store.isDarkMode)
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
                                Spacer().frame(height: store.scaled(80))
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
            // Pass-through: return event so the clicked toolbar control still fires on the first press.
            if store.isQuickSettingsPresented {
                let popoverFrame = store.quickSettingsPopoverFrame.insetBy(dx: -8, dy: -8)
                let submenuFrame = store.quickSettingsSubmenuFrame.insetBy(dx: -8, dy: -8)
                let buttonFrame = store.settingsButtonFrame.insetBy(dx: -4, dy: -4)
                let isInsidePopover = store.quickSettingsPopoverFrame.width > 0 && popoverFrame.contains(swiftUIPoint)
                let isInsideSubmenu = store.quickSettingsSubmenuFrame.width > 0 && submenuFrame.contains(swiftUIPoint)
                let isInsideButton = store.settingsButtonFrame.width > 0 && buttonFrame.contains(swiftUIPoint)
                if !isInsidePopover && !isInsideSubmenu && !isInsideButton {
                    store.isQuickSettingsPresented = false
                }
            }

            // When Downloads popover is open, dismiss when clicking outside its bounds (and the button)
            if store.isDownloadsPresented {
                let popoverFrame = store.downloadsPopoverFrame.insetBy(dx: -8, dy: -8)
                let buttonFrame = store.downloadsButtonFrame.insetBy(dx: -4, dy: -4)
                let isInsidePopover = store.downloadsPopoverFrame.width > 0 && popoverFrame.contains(swiftUIPoint)
                let isInsideButton = store.downloadsButtonFrame.width > 0 && buttonFrame.contains(swiftUIPoint)
                if !isInsidePopover && !isInsideButton {
                    store.isDownloadsPresented = false
                }
            }

            // When Extensions popover is open, dismiss when clicking outside its bounds (and the button)
            if store.isExtensionsPresented {
                let popoverFrame = store.extensionsPopoverFrame.insetBy(dx: -8, dy: -8)
                let buttonFrame = store.extensionsButtonFrame.insetBy(dx: -4, dy: -4)
                let isInsidePopover = store.extensionsPopoverFrame.width > 0 && popoverFrame.contains(swiftUIPoint)
                let isInsideButton = store.extensionsButtonFrame.width > 0 && buttonFrame.contains(swiftUIPoint)
                if !isInsidePopover && !isInsideButton {
                    store.isExtensionsPresented = false
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
                let paletteWidth = store.scaled(580)
                let x = max(0, (windowWidth - paletteWidth) / 2)
                effectivePaletteFrame = CGRect(
                    x: x,
                    y: store.scaled(72),
                    width: paletteWidth,
                    height: store.scaled(350)
                )
            }

            if effectivePaletteFrame.contains(swiftUIPoint) {
                return event
            } else {
                // Dismiss but let the click pass through so toolbar
                // buttons work on the first press, not the second.
                store.dismissFloatingOmnibar()
                return event
            }
        }

        // Monitor keyDown for registered custom shortcuts and Escape
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Intercept Escape (keyCode 53) to close quick settings, inline url bar, floating omnibar, new tab omnibar, or tab switcher
            if event.keyCode == 53 {
                if store.isExtensionsPresented {
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                        store.isExtensionsPresented = false
                    }
                    return nil
                }
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

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Leave Tab and Shift-Tab to WKWebView so websites can move focus through form fields.
            if event.keyCode == 48,
               !modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option) {
                return event
            }
            if modifiers.contains(.command),
               modifiers.isDisjoint(with: [.shift, .control, .option]),
               let number = topRowDigitByKeyCode[event.keyCode] {
                store.selectTab(number: number)
                return nil
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

            if modifiers.contains(.control), !modifiers.contains(.command), !modifiers.contains(.option) {
                switch event.charactersIgnoringModifiers {
                case "+", "=": store.zoomIn(); return nil
                case "-": store.zoomOut(); return nil
                case "0": store.resetZoom(); return nil
                default:
                    if event.keyCode == 69 || event.keyCode == 78 || event.keyCode == 82 {
                        if event.keyCode == 69 { store.zoomIn() }
                        else if event.keyCode == 78 { store.zoomOut() }
                        else { store.resetZoom() }
                        return nil
                    }
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
            Ph.magnifyingGlass.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
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
                Ph.caretDown.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 10, height: 10)
                    .foregroundColor(store.themeColors.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Find Next")

            Button {
                store.showsFindBar = false
                findQuery = ""
            } label: {
                Ph.x.bold
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 10, height: 10)
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

private struct SavedPasswordSuggestionOverlay: View {
    @ObservedObject var tab: LeanTab
    let isDark: Bool

    @ViewBuilder
    var body: some View {
        if let frame = tab.passwordSuggestionFrame, !tab.savedPasswordSuggestions.isEmpty {
            SavedPasswordSuggestions(
                logins: tab.savedPasswordSuggestions,
                isDark: isDark,
                select: tab.fillSavedPassword
            )
            .offset(x: frame.minX, y: frame.maxY + 6)
            .zIndex(30)
        }
    }
}

private struct SavedPasswordSuggestions: View {
    let logins: [SavedPassword]
    let isDark: Bool
    let select: (SavedPassword) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(logins) { login in
                Button { select(login) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 26, height: 26)
                            .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(login.username.isEmpty ? "Saved sign-in" : login.username)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(login.host)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                Text("From your Keychain")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 5)
            .padding(.bottom, 8)
        }
        .frame(width: 280, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isDark ? .white.opacity(0.13) : .black.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .padding(1)
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
        // Never use window-wide background dragging: with fullSizeContentView
        // it makes AppKit treat presses on SwiftUI controls as potential
        // window drags, so every button needs unnaturally still, repeated
        // clicks to fire. Dragging is owned explicitly by WindowDragView
        // surfaces behind the top bar / sidebar empty areas instead.
        window.isMovableByWindowBackground = false
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

// MARK: - Zoom Indicator HUD
private struct ZoomIndicatorView: View {
    @ObservedObject var store: LeanStore
    let zoom: Double

    private var percentageString: String {
        "\(Int((zoom * 100).rounded()))%"
    }

    private var primaryColor: Color {
        store.isDarkMode ? Color.white.opacity(0.96) : Color(white: 0.12)
    }

    private var secondaryColor: Color {
        store.isDarkMode ? Color.white.opacity(0.60) : Color(white: 0.12).opacity(0.62)
    }

    var body: some View {
        HStack(spacing: store.scaled(5)) {
            Text("Zoom")
                .font(store.bodyFont(size: 11))
                .foregroundColor(secondaryColor)

            Text(percentageString)
                .font(store.headingFont(size: 11.5))
                .foregroundColor(primaryColor)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, store.scaled(11))
        .padding(.vertical, store.scaled(6))
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(Capsule())
        )
        .background(
            (store.isDarkMode ? Color.black.opacity(0.65) : Color.white.opacity(0.80))
                .clipShape(Capsule())
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                    lineWidth: 0.75
                )
        )
        .shadow(
            color: Color.black.opacity(store.isDarkMode ? 0.28 : 0.08),
            radius: 8,
            x: 0,
            y: 3
        )
    }
}

// MARK: - Page Loading Bar
/// A luminous 2px hairline progress beam at the top edge of the web content card.
/// Visible in all modes (including Zen mode with no tab bar) since it lives
/// inside the content area itself, not in browser chrome.
///
/// Uses an internal `displayProgress` that follows real progress while loading,
/// then snaps to 1.0 when loading ends so the bar always visually completes
/// before fading — even when `isLoading` cuts off early at 70%.
private struct PageLoadingBar: View {
    let isLoading: Bool
    let progress: Double
    let isDark: Bool

    @State private var isVisible = false
    @State private var displayProgress: Double = 0
    @State private var shimmerPhase: CGFloat = -0.4
    @State private var isShimmering = false
    @State private var showDelayElapsed = false
    @State private var showWorkItem: DispatchWorkItem?
    @State private var dismissWorkItem: DispatchWorkItem?

    private let barHeight: CGFloat = 2

    private var progressColor: Color {
        isDark
            ? Color(red: 0.55, green: 0.65, blue: 1.0)
            : Color(red: 0.20, green: 0.40, blue: 0.95)
    }

    private var glowColor: Color {
        progressColor.opacity(isDark ? 0.50 : 0.35)
    }

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width

            if isVisible {
                ZStack(alignment: .leading) {
                    Color.clear.frame(height: barHeight)

                    // Progress fill
                    progressColor
                        .frame(width: totalWidth * max(displayProgress, 0.02), height: barHeight)

                    // Luminous shimmer sweep
                    if isShimmering {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: progressColor.opacity(0.6), location: 0.4),
                                .init(color: .white.opacity(isDark ? 0.5 : 0.7), location: 0.5),
                                .init(color: progressColor.opacity(0.6), location: 0.6),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: totalWidth * 0.35, height: barHeight)
                        .offset(x: shimmerPhase * totalWidth)
                        .mask(
                            Rectangle()
                                .frame(width: totalWidth * max(displayProgress, 0.02), height: barHeight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    }
                }
                .frame(height: barHeight)
                .shadow(color: glowColor, radius: 4, x: 0, y: 2)
                .allowsHitTesting(false)
                .transition(
                    .asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.15)),
                        removal: .opacity.animation(.easeInOut(duration: 0.30))
                    )
                )
            }
        }
        .frame(height: isVisible ? barHeight : 0)
        .clipped()
        .onAppear {
            if isLoading { handleLoadStart() }
        }
        .onChange(of: isLoading) { _, loading in
            if loading {
                handleLoadStart()
            } else {
                handleLoadEnd()
            }
        }
        .onChange(of: progress) { _, newProgress in
            // Only follow real progress while actively loading
            guard isLoading else { return }
            withAnimation(.spring(response: 0.40, dampingFraction: 0.88)) {
                displayProgress = min(newProgress, 0.95)
            }
        }
    }

    private func handleLoadStart() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        showWorkItem?.cancel()
        displayProgress = 0

        // Small delay to avoid flashing on instant navigations (cache hits)
        let workItem = DispatchWorkItem {
            showDelayElapsed = true
            withAnimation(.easeOut(duration: 0.12)) {
                isVisible = true
            }
            startShimmer()
        }
        showWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: workItem)
    }

    private func handleLoadEnd() {
        showWorkItem?.cancel()
        showWorkItem = nil

        guard showDelayElapsed else {
            // Navigation was so fast the bar never appeared — skip entirely
            isVisible = false
            showDelayElapsed = false
            return
        }

        // Step 1: Snap the bar to 100% with a fast spring
        withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
            displayProgress = 1.0
        }

        // Step 2: Stop shimmer
        stopShimmer()

        // Step 3: Fade out after the fill animation visually completes
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.28)) {
                isVisible = false
            }
            showDelayElapsed = false
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func startShimmer() {
        isShimmering = true
        shimmerPhase = -0.4
        withAnimation(
            .linear(duration: 1.1)
            .repeatForever(autoreverses: false)
        ) {
            shimmerPhase = 1.1
        }
    }

    private func stopShimmer() {
        withAnimation(.easeOut(duration: 0.25)) {
            shimmerPhase = 1.1
        }
        // Remove shimmer layer after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isShimmering = false
        }
    }
}

// MARK: - Split Tabs Container View

struct SplitTabsContainerView: View {
    @ObservedObject var parentTab: LeanTab
    @ObservedObject var store: LeanStore

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let count = parentTab.splitTabs.count
            let dividerCount = max(0, count - 1)
            let dividerWidth: CGFloat = 8
            let availableWidth = max(0, totalWidth - CGFloat(dividerCount) * dividerWidth)

            HStack(spacing: 0) {
                ForEach(Array(parentTab.splitTabs.enumerated()), id: \.element.id) { index, subTab in
                    let ratio = paneRatio(index: index, count: count)
                    let paneWidth = availableWidth * ratio

                    SplitPaneView(
                        parentTab: parentTab,
                        subTab: subTab,
                        index: index,
                        isFocused: index == parentTab.activeSplitIndex,
                        store: store
                    )
                    .frame(width: max(120, paneWidth))

                    if index < dividerCount {
                        SplitPaneDividerView(
                            index: index,
                            totalWidth: availableWidth,
                            parentTab: parentTab,
                            theme: store.adaptiveTheme
                        )
                    }
                }
            }
        }
    }

    private func paneRatio(index: Int, count: Int) -> CGFloat {
        if parentTab.splitWidthRatios.count != count {
            return 1.0 / CGFloat(max(1, count))
        }
        return parentTab.splitWidthRatios[index]
    }
}

private struct SplitPaneDividerView: View {
    let index: Int
    let totalWidth: CGFloat
    @ObservedObject var parentTab: LeanTab
    let theme: AdaptiveFrameTheme

    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    isDragging
                        ? theme.activeTabStroke
                        : (isHovered ? theme.activeTabStroke.opacity(0.6) : theme.webCardStroke.opacity(0.35))
                )
                .frame(width: 1)

            Capsule()
                .fill(
                    isDragging || isHovered
                        ? theme.primaryText.opacity(0.85)
                        : theme.primaryText.opacity(0.25)
                )
                .frame(width: 3.5, height: 26)
                .scaleEffect(isDragging || isHovered ? 1.15 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.12), value: isDragging)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDragging = true
                    handleDrag(translation: value.translation.width)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onTapGesture(count: 2) {
            let count = parentTab.splitTabs.count
            parentTab.splitWidthRatios = Array(repeating: 1.0 / CGFloat(max(1, count)), count: count)
        }
    }

    private func handleDrag(translation: CGFloat) {
        let count = parentTab.splitTabs.count
        if parentTab.splitWidthRatios.count != count {
            parentTab.splitWidthRatios = Array(repeating: 1.0 / CGFloat(max(1, count)), count: count)
        }
        let deltaRatio = translation / max(1, totalWidth)
        let minRatio: CGFloat = 0.12
        let maxRatio: CGFloat = 0.88

        let current1 = parentTab.splitWidthRatios[index]
        let current2 = parentTab.splitWidthRatios[index + 1]
        let new1 = min(max(current1 + deltaRatio, minRatio), maxRatio)
        let new2 = min(max(current2 - deltaRatio, minRatio), maxRatio)

        if new1 >= minRatio && new2 >= minRatio {
            parentTab.splitWidthRatios[index] = new1
            parentTab.splitWidthRatios[index + 1] = new2
        }
    }
}

private struct SplitPaneView: View {
    @ObservedObject var parentTab: LeanTab
    @ObservedObject var subTab: LeanTab
    let index: Int
    let isFocused: Bool
    @ObservedObject var store: LeanStore

    @State private var isEditingURL = false
    @State private var urlText = ""

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
                .frame(height: store.scaled(32))

            Group {
                if subTab.url != nil || subTab.isPageSource {
                    WebView(tab: subTab)
                        .id(subTab.id)
                } else {
                    SplitPaneEmptyView(tab: subTab, store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous)
                .fill(store.themeColors.windowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous)
                .stroke(
                    isFocused
                        ? Color(red: 0.18, green: 0.80, blue: 0.44)
                        : store.adaptiveTheme.webCardStroke.opacity(0.4),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .shadow(
            color: isFocused
                ? Color(red: 0.18, green: 0.80, blue: 0.44).opacity(store.isDarkMode ? 0.25 : 0.15)
                : store.adaptiveTheme.webCardShadow,
            radius: isFocused ? 6 : store.adaptiveTheme.webCardShadowRadius,
            x: 0,
            y: store.adaptiveTheme.isFrameLight ? 2 : 3
        )
        .contentShape(Rectangle())
        .onTapGesture {
            parentTab.activeSplitIndex = index
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var paneHeader: some View {
        HStack(spacing: 4) {
            InteractiveIconButton(
                icon: .caretLeft,
                helpText: "Back",
                size: 22,
                iconSize: 11,
                color: store.adaptiveTheme.secondaryText,
                hoverColor: store.adaptiveTheme.primaryText,
                disabledColor: store.adaptiveTheme.disabledIconText,
                hoverBackground: store.adaptiveTheme.iconHoverBackground,
                pressedBackground: store.adaptiveTheme.iconPressedBackground,
                isDark: store.adaptiveTheme.effectiveIsDark,
                isEnabled: subTab.canGoBack
            ) {
                parentTab.activeSplitIndex = index
                subTab.goBack()
            }

            InteractiveIconButton(
                icon: .caretRight,
                helpText: "Forward",
                size: 22,
                iconSize: 11,
                color: store.adaptiveTheme.secondaryText,
                hoverColor: store.adaptiveTheme.primaryText,
                disabledColor: store.adaptiveTheme.disabledIconText,
                hoverBackground: store.adaptiveTheme.iconHoverBackground,
                pressedBackground: store.adaptiveTheme.iconPressedBackground,
                isDark: store.adaptiveTheme.effectiveIsDark,
                isEnabled: subTab.canGoForward
            ) {
                parentTab.activeSplitIndex = index
                subTab.goForward()
            }

            InteractiveIconButton(
                icon: .arrowClockwise,
                helpText: "Reload",
                size: 22,
                iconSize: 11,
                color: store.adaptiveTheme.secondaryText,
                hoverColor: store.adaptiveTheme.primaryText,
                disabledColor: store.adaptiveTheme.disabledIconText,
                hoverBackground: store.adaptiveTheme.iconHoverBackground,
                pressedBackground: store.adaptiveTheme.iconPressedBackground,
                isDark: store.adaptiveTheme.effectiveIsDark,
                isEnabled: subTab.url != nil
            ) {
                parentTab.activeSplitIndex = index
                subTab.reload()
            }

            Spacer(minLength: 4)

            Button {
                parentTab.activeSplitIndex = index
                urlText = subTab.url?.absoluteString ?? ""
                isEditingURL.toggle()
            } label: {
                HStack(spacing: 4) {
                    TabFaviconView(tab: subTab, isDark: store.adaptiveTheme.effectiveIsDark, size: 12)

                    Text(subTab.url?.host ?? (subTab.title.isEmpty ? "New Tab" : subTab.title))
                        .font(store.tabTitleFont(size: 11.5))
                        .foregroundColor(
                            isFocused
                                ? store.adaptiveTheme.primaryText
                                : store.adaptiveTheme.secondaryText
                        )
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    isFocused
                        ? store.adaptiveTheme.activeTabStroke.opacity(0.12)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isEditingURL) {
                HStack(spacing: 6) {
                    TextField("Search or enter URL", text: $urlText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(6)
                        .frame(width: 240)
                        .onSubmit {
                            let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty, let target = AddressResolver.resolve(trimmed, searchEngine: store.searchEngine) {
                                subTab.load(target)
                            }
                            isEditingURL = false
                        }
                }
                .padding(6)
            }

            Spacer(minLength: 4)

            if subTab.isPlayingMedia {
                TabMediaIndicatorView(tab: subTab, theme: store.adaptiveTheme, compact: true)
            }

            InteractiveIconButton(
                icon: .x,
                helpText: "Close split pane",
                size: 22,
                iconSize: 9,
                color: store.adaptiveTheme.secondaryText,
                hoverColor: store.adaptiveTheme.primaryText,
                disabledColor: store.adaptiveTheme.disabledIconText,
                hoverBackground: store.adaptiveTheme.iconHoverBackground,
                pressedBackground: store.adaptiveTheme.iconPressedBackground,
                isDark: store.adaptiveTheme.effectiveIsDark,
                isEnabled: true
            ) {
                store.closeSplitPane(in: parentTab, pane: subTab)
            }
        }
        .padding(.horizontal, 6)
        .background(
            store.adaptiveTheme.activeTabBackground.opacity(0.75)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(store.adaptiveTheme.webCardStroke.opacity(0.35))
                .frame(height: 1)
        }
    }
}

private struct SplitPaneEmptyView: View {
    @ObservedObject var tab: LeanTab
    @ObservedObject var store: LeanStore

    @State private var query = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Ph.compass.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.5))

            HStack(spacing: 8) {
                Ph.magnifyingGlass.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundColor(store.adaptiveTheme.secondaryText)

                TextField("Search or enter address", text: $query)
                    .textFieldStyle(.plain)
                    .font(store.tabTitleFont(size: 13))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                    .focused($isFocused)
                    .onSubmit {
                        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty, let target = AddressResolver.resolve(trimmed, searchEngine: store.searchEngine) {
                            tab.load(target)
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 320)
            .background(
                store.adaptiveTheme.activeTabBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(store.adaptiveTheme.activeTabStroke.opacity(0.3), lineWidth: 1)
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(store.themeColors.windowBackground)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}
