import SwiftUI
import WebKit

struct LeanView: View {
    @ObservedObject var store: LeanStore
    @State private var findQuery = ""
    @State private var hasSetupKeyMonitor = false

    @State private var isZenTopBarRevealed = false
    @State private var hideTopBarWorkItem: DispatchWorkItem?

    private var isTopBarVisible: Bool {
        if !store.enableZenMode {
            return true
        }
        if store.selectedTab?.url == nil {
            return true
        }
        return isZenTopBarRevealed
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
            hideTopBarWorkItem?.cancel()
            let item = DispatchWorkItem {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isZenTopBarRevealed = false
                }
            }
            hideTopBarWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
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

                // Main Content Area
                ZStack {
                    (store.enableWindowBorder ? Color.clear : store.themeColors.windowBackground)
                        .ignoresSafeArea()

                    let cardSidePadding: CGFloat = store.enableWindowBorder ? store.windowBorderWidth : 0
                    let cardBottomPadding: CGFloat = store.enableWindowBorder ? store.windowBorderWidth : 0
                    let cardTopPadding: CGFloat = store.enableWindowBorder ? (isTopBarVisible ? 2 : store.windowBorderWidth) : 0

                    if let tab = store.selectedTab {
                        if tab.isSettingsPage {
                            SettingsView(store: store)
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
                                .padding(.horizontal, cardSidePadding)
                                .padding(.bottom, cardBottomPadding)
                                .padding(.top, cardTopPadding)
                        } else if tab.url != nil {
                            // Web Page Loaded
                            ZStack(alignment: .topTrailing) {
                                WebView(tab: tab)
                                    .id(tab.id)

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
                        .padding(.horizontal, cardSidePadding)
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
                        .padding(.horizontal, cardSidePadding)
                        .padding(.bottom, cardBottomPadding)
                        .padding(.top, cardTopPadding)
                    }
                }
            }
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

            // Top Hover Detection Zone (invisible trigger active at top edge in Zen mode when top bar is hidden)
            if store.enableZenMode && !isTopBarVisible {
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
        }
        .ignoresSafeArea(.all)
        .background(
            store.enableWindowBorder
                ? AnyView(store.effectiveZenColor.ignoresSafeArea())
                : AnyView(store.themeColors.windowBackground.ignoresSafeArea())
        )
        .background(WindowConfigurator(store: store, isTopBarVisible: isTopBarVisible))
        .preferredColorScheme(store.colorScheme)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isTopBarVisible)
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
    }

    private func setupKeyMonitor() {
        guard !hasSetupKeyMonitor else { return }
        hasSetupKeyMonitor = true

        // Monitor mouse clicks when inline URL bar or floating omnibar is open:
        // Only clicking outside the active region collapses / closes it!
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            guard let window = event.window ?? NSApp.keyWindow else { return event }

            // Convert AppKit window coordinates (origin bottom-left) to SwiftUI global coordinates (origin top-left)
            let windowHeight = window.contentView?.frame.height ?? window.frame.height
            let clickLocation = event.locationInWindow
            let swiftUIPoint = CGPoint(x: clickLocation.x, y: windowHeight - clickLocation.y)

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

        // Monitor keyDown for Cmd+W, Cmd+T, Cmd+L, Ctrl+Tab, Ctrl+Shift+Tab, Escape
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
            let isCommand = event.modifierFlags.contains(.command) &&
                !event.modifierFlags.contains(.shift) &&
                !event.modifierFlags.contains(.control) &&
                !event.modifierFlags.contains(.option)

            // Intercept Cmd+W to close current tab instead of the entire window / application
            if isCommand && (event.keyCode == 13 || event.charactersIgnoringModifiers?.lowercased() == "w") {
                store.closeSelectedTab()
                return nil // Prevent event from closing the window!
            }

            // Intercept Cmd+T for floating omnibar / new tab command (keyCode 17 = 'T')
            if isCommand && (event.keyCode == 17 || event.charactersIgnoringModifiers?.lowercased() == "t") {
                store.handleNewTabCommand()
                return nil
            }

            // Intercept Cmd+L to focus inline address bar or new tab address (keyCode 37 = 'L')
            if isCommand && (event.keyCode == 37 || event.charactersIgnoringModifiers?.lowercased() == "l") {
                if store.selectedTab?.url != nil {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        store.isInlineURLEditing = true
                    }
                } else {
                    NotificationCenter.default.post(name: .focusAddress, object: nil)
                }
                return nil
            }

            // Intercept Escape (keyCode 53) to close inline url bar, floating omnibar, new tab omnibar, or tab switcher
            if event.keyCode == 53 {
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

            // Intercept Ctrl+Tab or Ctrl+Shift+Tab
            if event.keyCode == 48 && flags.contains(.control) {
                let isShift = flags.contains(.shift)
                if store.enableThumbnailsInTabSwitcher {
                    store.startTabSwitcher(reverse: isShift)
                } else {
                    store.selectNextTab(reverse: isShift)
                }
                return nil
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

private struct WindowConfigurator: NSViewRepresentable {
    @ObservedObject var store: LeanStore
    let isTopBarVisible: Bool

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

        let targetAlpha: CGFloat = (!store.enableZenMode || isTopBarVisible) ? 1.0 : 0.0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.standardWindowButton(.closeButton)?.animator().alphaValue = targetAlpha
            window.standardWindowButton(.miniaturizeButton)?.animator().alphaValue = targetAlpha
            window.standardWindowButton(.zoomButton)?.animator().alphaValue = targetAlpha
        }
    }
}

extension Notification.Name {
    static let focusAddress = Notification.Name("Lean.focusAddress")
    static let showFind = Notification.Name("Lean.showFind")
    static let showSettings = Notification.Name("Lean.showSettings")
}
