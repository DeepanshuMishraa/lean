import AppKit
import SwiftUI
import WebKit

@MainActor
final class LeanTab: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    private let dataStore: WKWebsiteDataStore
    private let initialConfiguration: WKWebViewConfiguration?
    private var isDark: Bool
    private var storedWebView: LeanWebView?
    private var sleepingInteractionState: Any?
    private var pendingNavigationID = UUID()
    var popupOpenerID: LeanTab.ID?
    var hasActivePopup = false

    var hasWebView: Bool { storedWebView != nil }

    var webView: LeanWebView {
        if let storedWebView { return storedWebView }
        return createWebView()
    }

    @Published private(set) var title = "New Tab"
    @Published private(set) var url: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var loadingProgress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var pageZoom = 1.0
    @Published private(set) var isZoomIndicatorVisible = false
    @Published private(set) var isSleeping = false
    @Published var snapshot: NSImage? = nil
    @Published var favicon: NSImage? = nil
    private(set) var scrollbarStyle: ScrollbarStyle
    private(set) var smoothScrollingEnabled: Bool
    private(set) var pageFont: LeanFont
    private(set) var pageHeadingWeight: Int
    private(set) var pageBodyWeight: Int
    private(set) var adBlockingEnabled: Bool
    private(set) var adBlockingExcludedHosts: Set<String>
    private(set) var passwordSavePromptsEnabled: Bool
    private(set) var passwordSuggestionsEnabled: Bool
    private var pendingLogin: (origin: URL, username: String, password: String, submittedAt: Date)?
    private var restoreScrollPosition: CGPoint?
    private var policyHost: String?

    var isSettingsPage: Bool {
        guard let url = url else { return false }
        return url.absoluteString == "lean://settings" || (url.scheme == "lean" && url.host == "settings")
    }

    /// Source-viewer tab. Keeps `url == nil` (so it never pollutes history
    /// or session restore) — LeanView mounts the web view for these
    /// explicitly instead of via `url != nil`.
    private(set) var isPageSource = false

    var onStateChange: (() -> Void)?
    var onOpenNewTab: ((URL, WKWebViewConfiguration) -> WKWebView?)?
    var onCloseTab: (() -> Void)?
    var onOpenURLInNewTab: ((URL) -> Void)?
    var onOpenSourceTab: ((String, String?) -> LeanTab?)?
    var downloadManager: DownloadManager?
    var mediaPermissionStore: MediaPermissionStore?
    private var progressObserver: NSKeyValueObservation?
    private var navigationObservers: [NSKeyValueObservation] = []
    private var activeDownloadIDs: [ObjectIdentifier: UUID] = [:]
    private var downloadProgressObservers: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var downloadLastSample: [UUID: (bytes: Int64, date: Date, speed: Double)] = [:]
    private var activeDownloadObjects: [UUID: WKDownload] = [:]
    private var zoomIndicatorWorkItem: DispatchWorkItem?

    func cancelActiveDownload(id: UUID) {
        activeDownloadObjects[id]?.cancel()
        activeDownloadObjects[id] = nil
    }

    init(
        dataStore: WKWebsiteDataStore,
        initialURL: URL?,
        isDark: Bool = false,
        scrollbarStyle: ScrollbarStyle = .normal,
        smoothScrolling: Bool = true,
        pageFont: LeanFont = .system,
        pageHeadingWeight: Int = 0,
        pageBodyWeight: Int = 0,
        adBlockingEnabled: Bool = true,
        adBlockingExcludedHosts: Set<String> = [],
        passwordSavePromptsEnabled: Bool = true,
        passwordSuggestionsEnabled: Bool = true,
        configuration: WKWebViewConfiguration? = nil
    ) {
        self.dataStore = dataStore
        if let configuration {
            configuration.userContentController = WKUserContentController()
        }
        self.initialConfiguration = configuration
        self.isDark = isDark
        self.scrollbarStyle = scrollbarStyle
        self.smoothScrollingEnabled = smoothScrolling
        self.pageFont = pageFont
        self.pageHeadingWeight = pageHeadingWeight
        self.pageBodyWeight = pageBodyWeight
        self.adBlockingEnabled = adBlockingEnabled
        self.adBlockingExcludedHosts = adBlockingExcludedHosts
        self.passwordSavePromptsEnabled = passwordSavePromptsEnabled
        self.passwordSuggestionsEnabled = passwordSuggestionsEnabled
        self.policyHost = initialURL?.host?.lowercased()
        super.init()
        self.url = initialURL
        if initialURL?.scheme == "lean" && (initialURL?.host == "settings" || initialURL?.absoluteString == "lean://settings") {
            self.title = "Settings"
        } else if let host = initialURL?.host {
            self.title = host
            updateFavicon()
        }

        if let initialURL {
            self.load(initialURL)
        }
    }

    private func createWebView() -> LeanWebView {
        // The popup configuration was sanitized in init, but keeping the
        // configuration preserves its process pool for shared OAuth/SSO state.
        let effectiveConfiguration = initialConfiguration ?? WKWebViewConfiguration()
        let configuration = effectiveConfiguration
        configuration.websiteDataStore = dataStore
        if #available(macOS 15.4, *) {
            configuration.webExtensionController = BrowserExtensionManager.shared.controller
        }
        configuration.preferences.isElementFullscreenEnabled = true

        // Register custom scrollbar script at document start so it styles before first paint!
        let scrollbarScript = WKUserScript(
            source: PageScripts.scrollbar(scrollbarStyle),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(scrollbarScript)

        let fontScript = WKUserScript(
            source: PageScripts.font(pageFont, headingWeight: pageHeadingWeight, bodyWeight: pageBodyWeight),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(fontScript)

        // Register custom smooth scrolling script at document end
        let smoothScript = WKUserScript(
            source: PageScripts.smoothScrolling(enabled: smoothScrollingEnabled),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(smoothScript)
        let youtubeAdsScript = WKUserScript(
            source: PageScripts.youtubeAds(enabled: isBlockingEnabledForCurrentHost),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(youtubeAdsScript)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: PageScripts.pageReady,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: PageScripts.contextMenuLinkTracker,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(source: PageScripts.audioActivity, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        addPasswordCaptureScript(to: configuration.userContentController)

        let webView = LeanWebView(frame: .zero, configuration: configuration)
        storedWebView = webView
        webView.configuration.userContentController.add(self, name: PageScripts.pageReadyMessageName)
        webView.configuration.userContentController.add(self, name: PageScripts.contextMenuMessageName)
        webView.configuration.userContentController.add(self, name: PageScripts.passwordFormMessageName)
        webView.contextMenuHook = { [weak self] menu in
            self?.appendPageMenuItems(to: menu)
        }
        // Enable full opaque hardware acceleration and layer backing
        webView.wantsLayer = true
        webView.layer?.drawsAsynchronously = true
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = isDark ? NSColor.black : NSColor.white
        }

        // Standard Desktop Safari User-Agent ensures YouTube, Google, Twitter, etc. send full desktop content
        let defaultSafariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        webView.customUserAgent = defaultSafariUA

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        // Web Inspector is user-facing via the right-click menu's
        // Inspect Element item, so stay inspectable in all builds.
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            let progress = webView.estimatedProgress
            DispatchQueue.main.async {
                guard let self, self.storedWebView === webView, webView.estimatedProgress == progress else { return }
                self.loadingProgress = progress
                if progress >= 0.7, self.isLoading {
                    self.isLoading = false
                    self.refreshState()
                }
            }
        }
        navigationObservers = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.canGoBack = webView.canGoBack
                    self.onStateChange?()
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.canGoForward = webView.canGoForward
                    self.onStateChange?()
                }
            }
        ]

        syncContentRuleLists()
        if isSleeping, let restoreURL = url {
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.restoreSleepingWebView(webView, url: restoreURL)
            }
        }
        return webView
    }

    func applyAdBlocking(_ enabled: Bool, excluding excludedHosts: Set<String>) {
        let wasBlocking = isBlockingEnabledForCurrentHost
        adBlockingEnabled = enabled
        adBlockingExcludedHosts = excludedHosts
        guard let webView = storedWebView else { return }
        let shouldBlock = isBlockingEnabledForCurrentHost
        rebuildUserScripts(syncRuleLists: false)
        webView.evaluateJavaScript(PageScripts.youtubeAdsLive(enabled: shouldBlock)) { _, _ in }
        syncContentRuleLists {
            if wasBlocking != shouldBlock, !self.isLoading { webView.reload() }
        }
    }

    private var isBlockingEnabledForCurrentHost: Bool {
        SiteBlockingPolicy.shouldBlock(
            globalEnabled: adBlockingEnabled,
            host: policyHost ?? storedWebView?.url?.host ?? url?.host,
            excludedHosts: adBlockingExcludedHosts
        )
    }

    /// Adds/removes the compiled content-rule lists without touching scripts.
    private func syncContentRuleLists(completion: (() -> Void)? = nil) {
        guard let webView = storedWebView else { completion?(); return }
        Task { [weak self] in
            let ruleLists = await ContentBlocker.ruleLists()
            guard let self else { completion?(); return }
            if self.isBlockingEnabledForCurrentHost {
                for ruleList in ruleLists {
                    webView.configuration.userContentController.remove(ruleList)
                    webView.configuration.userContentController.add(ruleList)
                }
            } else {
                for ruleList in ruleLists {
                    webView.configuration.userContentController.remove(ruleList)
                }
            }
            completion?()
        }
    }

    func applyTheme(isDark: Bool) {
        self.isDark = isDark
        guard let webView = storedWebView else { return }
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = isDark ? NSColor.black : NSColor.white
        }
    }

    private func addPasswordCaptureScript(to controller: WKUserContentController) {
        guard passwordSavePromptsEnabled else { return }
        controller.addUserScript(
            WKUserScript(
                source: PageScripts.passwordFormSubmit,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
    }

    func applyPasswordPreferences(savePromptsEnabled: Bool, suggestionsEnabled: Bool) {
        let promptsChanged = passwordSavePromptsEnabled != savePromptsEnabled
        passwordSavePromptsEnabled = savePromptsEnabled
        passwordSuggestionsEnabled = suggestionsEnabled
        if !savePromptsEnabled { pendingLogin = nil }
        if promptsChanged, storedWebView != nil {
            rebuildUserScripts()
        }
    }

    private func rebuildUserScripts(syncRuleLists: Bool = true) {
        webView.configuration.userContentController.removeAllUserScripts()
        let scrollbarScript = WKUserScript(
            source: PageScripts.scrollbar(scrollbarStyle),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        webView.configuration.userContentController.addUserScript(scrollbarScript)

        let fontScript = WKUserScript(
            source: PageScripts.font(pageFont, headingWeight: pageHeadingWeight, bodyWeight: pageBodyWeight),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        webView.configuration.userContentController.addUserScript(fontScript)

        let smoothScript = WKUserScript(
            source: PageScripts.smoothScrolling(enabled: smoothScrollingEnabled),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        webView.configuration.userContentController.addUserScript(smoothScript)
        let youtubeAdsScript = WKUserScript(
            source: PageScripts.youtubeAds(enabled: isBlockingEnabledForCurrentHost),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        webView.configuration.userContentController.addUserScript(youtubeAdsScript)
        webView.configuration.userContentController.addUserScript(
            WKUserScript(
                source: PageScripts.pageReady,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        webView.configuration.userContentController.addUserScript(
            WKUserScript(
                source: PageScripts.contextMenuLinkTracker,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        webView.configuration.userContentController.addUserScript(
            WKUserScript(source: PageScripts.audioActivity, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        addPasswordCaptureScript(to: webView.configuration.userContentController)

        if syncRuleLists { syncContentRuleLists() }
    }

    func applyScrollbarStyle(_ style: ScrollbarStyle) {
        self.scrollbarStyle = style
        guard let webView = storedWebView else { return }
        rebuildUserScripts()
        let script = PageScripts.scrollbar(style)
        webView.evaluateJavaScript(script) { _, _ in }
    }

    func applySmoothScrolling(_ enabled: Bool) {
        self.smoothScrollingEnabled = enabled
        guard let webView = storedWebView else { return }
        rebuildUserScripts()
        let script = PageScripts.smoothScrolling(enabled: enabled)
        webView.evaluateJavaScript(script) { _, _ in }
    }

    func applyPageFont(_ font: LeanFont, headingWeight: Int = 0, bodyWeight: Int = 0) {
        pageFont = font
        pageHeadingWeight = headingWeight
        pageBodyWeight = bodyWeight
        guard let webView = storedWebView else { return }
        rebuildUserScripts()
        webView.evaluateJavaScript(PageScripts.font(font, headingWeight: headingWeight, bodyWeight: bodyWeight)) { _, _ in }
    }


    func displayTitle(isSelected: Bool, showFullTitle: Bool = true) -> String {
        if isSettingsPage {
            return "Settings"
        }
        if isSelected && showFullTitle {
            // When we are on a site and showFullTitle is enabled, show its full title
            return title.isEmpty ? "New Tab" : title
        } else {
            // Show clean short name / domain
            guard let url else { return "New Tab" }
            if let host = url.host?.lowercased().replacingOccurrences(of: "www.", with: "") {
                if host == "officecommun.com" { return "Office Commun" }
                if host == "x.com" || host == "twitter.com" { return "X" }
                if host == "youtube.com" { return "YouTube" }
                if host == "claude.ai" { return "Claude" }
                if host == "github.com" { return "GitHub" }
                if host == "slack.com" { return "Slack" }
                if host == "google.com" { return "Google" }
                if host == "apple.com" { return "Apple" }
                return host
            }
            return title.components(separatedBy: " - ").first?
                .components(separatedBy: " | ").first?
                .components(separatedBy: " : ").first?
                .trimmingCharacters(in: .whitespaces) ?? title
        }
    }

    func load(_ url: URL) {
        pendingNavigationID = UUID()
        let navigationID = pendingNavigationID
        if isSleeping {
            isSleeping = false
            sleepingInteractionState = nil
            restoreScrollPosition = nil
        }
        isPageSource = false
        self.url = url
        if title == "New Tab" || title.isEmpty {
            self.title = url.host ?? "Loading..."
        }
        if url.scheme == "lean" && (url.host == "settings" || url.absoluteString == "lean://settings") {
            self.title = "Settings"
            self.isLoading = false
            self.favicon = nil
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
            onStateChange?()
            return
        }
        loadingProgress = 0
        isLoading = true
        onStateChange?()
        updateFavicon(for: url)
        Task { @MainActor [weak self] in
            if #available(macOS 15.4, *) { await BrowserExtensionManager.shared.waitUntilReady() }
            guard let self, self.pendingNavigationID == navigationID, self.url == url else { return }
            self.webView.load(URLRequest(url: url))
        }
    }

    func submit(_ input: String) {
        guard let url = AddressResolver.resolve(input) else { return }
        load(url)
    }

    func goBack() {
        isLoading = true
        onStateChange?()
        webView.goBack()
    }
    func goForward() {
        isLoading = true
        onStateChange?()
        webView.goForward()
    }
    func reload() {
        if isSleeping, let url { load(url); return }
        isLoading = true
        onStateChange?()
        webView.reload()
    }
    func reloadFromOrigin() {
        if isSleeping, let url { load(url); return }
        isLoading = true
        onStateChange?()
        webView.reloadFromOrigin()
    }
    func stop() {
        isLoading = false
        webView.stopLoading()
        onStateChange?()
    }

    // MARK: - Page context menu

    /// Latest link under a right-click, reported by the injected tracker.
    private var lastContextLink: (url: URL, at: Date)?

    private var freshContextLinkURL: URL? {
        guard let last = lastContextLink, Date().timeIntervalSince(last.at) < 2 else { return nil }
        return last.url
    }

    private func appendPageMenuItems(to menu: NSMenu) {
        // Our items all target self; WebKit's don't. Strip ours first so a
        // reused menu object never accumulates duplicates across opens.
        menu.items
            .filter { $0.target === self }
            .forEach { menu.removeItem($0) }

        // WebKit already supplies Back/Forward/Reload — only add what it lacks.
        if let linkURL = freshContextLinkURL {
            let open = NSMenuItem(title: "Open Link in New Tab", action: #selector(pageMenuOpenLink(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = linkURL.absoluteString
            menu.insertItem(open, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        if passwordSuggestionsEnabled,
           let currentURL = url,
           currentURL.scheme?.lowercased() == "https",
           currentURL.host != nil,
           case .success(let logins) = PasswordVault.forOrigin(currentURL),
           !logins.isEmpty {
            let fill = NSMenuItem(title: "Fill Saved Sign-In…", action: #selector(pageMenuFillSavedPassword), keyEquivalent: "")
            fill.target = self
            menu.addItem(fill)
            menu.addItem(.separator())
        }
        let printItem = NSMenuItem(title: "Print...", action: #selector(pageMenuPrint), keyEquivalent: "")
        printItem.target = self
        printItem.isEnabled = !isSettingsPage
        menu.addItem(printItem)
        let source = NSMenuItem(title: "View Page Source", action: #selector(pageMenuShowSource), keyEquivalent: "")
        source.target = self
        menu.addItem(source)
    }

    @objc private func pageMenuOpenLink(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let url = URL(string: raw) else { return }
        if ExternalLinkPolicy.shouldOpenExternally(url) {
            NSWorkspace.shared.open(url)
        } else {
            onOpenURLInNewTab?(url)
        }
    }
    @objc private func pageMenuShowSource() { showPageSource() }
    @objc private func pageMenuPrint() { printPage() }

    @objc private func pageMenuFillSavedPassword() {
        guard passwordSuggestionsEnabled,
              let origin = url,
              origin.scheme?.lowercased() == "https",
              case .success(let logins) = PasswordVault.forOrigin(origin),
              !logins.isEmpty else { return }
        chooseLoginToFill(logins, origin: origin)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(pageMenuPrint) { return !isSettingsPage }
        return true
    }

    func showPageSource() {
        // Open the tab synchronously so it paints instantly; the DOM
        // serialization roundtrip fills it in when it lands.
        let title = "Source of \(self.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? self.url?.host ?? "page")"
        let tab = onOpenSourceTab?(title, nil)
        webView.evaluateJavaScript(
            "document.documentElement ? document.documentElement.outerHTML : ''"
        ) { [weak tab] result, _ in
            guard let tab else { return }
            guard let html = result as? String, !html.isEmpty else {
                tab.presentPageSource(title: title, html: "Unable to retrieve page source.")
                return
            }
            tab.presentPageSource(title: title, html: html)
        }
    }

    /// Presents source HTML in this tab. A nil body shows a loading
    /// placeholder until the real source arrives.
    func presentPageSource(title: String, html: String?) {
        self.title = title
        self.url = nil
        self.isPageSource = true
        self.favicon = nil
        self.isLoading = false
        let body = html.map(Self.escapedHTML) ?? "Loading page source…"
        let page = """
        <html><head><meta charset="utf-8"><title>\(Self.escapedHTML(title))</title>\
        <style>body{background:#fff;color:#222;font:12px/1.5 -apple-system,monospace;margin:16px;white-space:pre-wrap;word-break:break-all}\
        @media(prefers-color-scheme:dark){body{background:#1e1e1e;color:#d4d4d4}}</style>\
        </head><body>\(body)</body></html>
        """
        webView.loadHTMLString(page, baseURL: nil)
        onStateChange?()
    }

    nonisolated static func escapedHTML(_ string: String) -> String {
        var escaped = string.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        return escaped
    }

    /// Window for modal sheets (alerts, auth, media permission).
    private var sheetWindow: NSWindow? {
        webView.window
    }

    func destroy() {
        sleepingInteractionState = nil
        restoreScrollPosition = nil
        isSleeping = false
        progressObserver?.invalidate()
        progressObserver = nil
        navigationObservers.forEach { $0.invalidate() }
        navigationObservers.removeAll()
        isLoading = false
        onStateChange = nil
        onOpenNewTab = nil
        onCloseTab = nil
        onOpenURLInNewTab = nil
        onOpenSourceTab = nil
        guard let webView = storedWebView else { return }
        webView.contextMenuHook = nil

        // 1. Pause and remove all audio/video elements immediately
        let stopMediaJS = """
        (function() {
            try {
                var media = document.querySelectorAll('audio, video');
                for (var i = 0; i < media.length; i++) {
                    media[i].pause();
                    media[i].src = '';
                    media[i].load();
                }
            } catch(e) {}
        })();
        """
        webView.evaluateJavaScript(stopMediaJS, completionHandler: nil)

        // 2. Stop loading any pending network requests
        webView.stopLoading()

        // 3. Pause all page activities (timers, WebAudio, animation frames)
        if #available(macOS 12.0, *) {
            webView.pauseAllMediaPlayback()
            webView.setAllMediaPlaybackSuspended(true)
        }

        // 4. Detach delegates so no callbacks trigger
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        // 5. Load blank HTML page to completely flush DOM and WebAudio contexts
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)

        // 6. Remove all user scripts and message handlers
        webView.configuration.userContentController.removeScriptMessageHandler(forName: PageScripts.pageReadyMessageName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: PageScripts.contextMenuMessageName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: PageScripts.passwordFormMessageName)
        webView.configuration.userContentController.removeAllUserScripts()
        zoomIndicatorWorkItem?.cancel()
        webView.removeFromSuperview()
    }

    func zoomIn() { setPageZoom(pageZoom + 0.1) }
    func zoomOut() { setPageZoom(pageZoom - 0.1) }
    func resetZoom() { setPageZoom(1.0) }

    private func setPageZoom(_ zoom: Double) {
        guard !isSettingsPage, url != nil || isPageSource else { return }
        let clamped = min(max((zoom * 10).rounded() / 10, 0.5), 3.0)
        pageZoom = clamped
        webView.pageZoom = clamped
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            isZoomIndicatorVisible = true
        }
        zoomIndicatorWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.28)) {
                self?.isZoomIndicatorVisible = false
            }
            self?.onStateChange?()
        }
        zoomIndicatorWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
        onStateChange?()
    }

    func printPage() {
        guard !isSettingsPage, let window = webView.window else { return }
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        let operation = webView.printOperation(with: printInfo)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func find(_ query: String) {
        guard !query.isEmpty else { return }
        webView.find(query, configuration: WKFindConfiguration()) { _ in }
    }

    func requestSleep(while shouldRemainInactive: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        guard let webView = storedWebView,
              let scheme = webView.url?.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              TabSleepPolicy.canCommitSleep(
                sleepConditions(in: webView, isSelected: false, isPlayingMedia: false, hasUnsavedFormInput: false),
                isStillInactive: shouldRemainInactive()
              ) else {
            completion(false)
            return
        }
        inspectPageForSleep(webView) { [weak self, weak webView] activity in
            guard let self, let webView, let activity,
                  TabSleepPolicy.canCommitSleep(
                    self.sleepConditions(in: webView, isSelected: false, isPlayingMedia: activity.isPlayingMedia, hasUnsavedFormInput: activity.hasUnsavedFormInput),
                    isStillInactive: shouldRemainInactive()
                  ) else {
                completion(false)
                return
            }
            let configuration = WKSnapshotConfiguration()
            configuration.snapshotWidth = 220
            webView.takeSnapshot(with: configuration) { [weak self, weak webView] image, _ in
                DispatchQueue.main.async {
                    guard let self, let webView, let image, shouldRemainInactive() else {
                        completion(false)
                        return
                    }
                    self.inspectPageForSleep(webView) { latestActivity in
                        guard let latestActivity,
                              TabSleepPolicy.canCommitSleep(
                                self.sleepConditions(in: webView, isSelected: false, isPlayingMedia: latestActivity.isPlayingMedia, hasUnsavedFormInput: latestActivity.hasUnsavedFormInput),
                                isStillInactive: shouldRemainInactive()
                              ) else {
                            completion(false)
                            return
                        }
                        self.snapshot = image
                        self.restoreScrollPosition = latestActivity.scrollPosition
                        self.sleepingInteractionState = webView.interactionState
                        self.title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? self.title
                        self.url = webView.url
                        self.releaseWebViewForSleep(webView)
                        self.isSleeping = true
                        self.onStateChange?()
                        completion(true)
                    }
                }
            }
        }
    }

    private struct PageSleepActivity {
        let isPlayingMedia: Bool
        let hasUnsavedFormInput: Bool
        let scrollPosition: CGPoint
    }

    private func inspectPageForSleep(_ webView: WKWebView, completion: @escaping (PageSleepActivity?) -> Void) {
        let script = """
        (() => {
          const seen = new Set();
          const scan = doc => {
            if (!doc || seen.has(doc)) return { media: false, dirty: false, blocked: false };
            seen.add(doc);
            const mediaElements = Array.from(doc.querySelectorAll('audio, video')).some(item => !item.paused && !item.ended);
            const audioContexts = doc.defaultView && doc.defaultView.__leanAudioContexts || [];
            const webAudio = audioContexts.some(ref => {
              const context = ref.deref();
              return context && context.state === 'running';
            });
            const media = mediaElements || webAudio;
            const dirty = Array.from(doc.querySelectorAll('input, textarea, select')).some(field => {
              if (field.disabled || field.type === 'hidden') return false;
              if (field.type === 'checkbox' || field.type === 'radio') return field.checked !== field.defaultChecked;
              if (field instanceof HTMLSelectElement) return Array.from(field.options).some(option => option.selected !== option.defaultSelected);
              return field.value !== field.defaultValue;
            }) || Array.from(doc.querySelectorAll('[contenteditable=true]')).some(field => field.textContent.trim().length > 0);
            let blocked = false;
            for (const frame of doc.querySelectorAll('iframe')) {
              try {
                const rawURL = frame.getAttribute('src');
                const inheritsOrigin = !rawURL || rawURL === 'about:blank' || frame.hasAttribute('srcdoc');
                const frameURL = new URL(rawURL || 'about:blank', doc.location.href);
                const opaqueSandbox = frame.hasAttribute('sandbox') && !frame.sandbox.contains('allow-same-origin');
                if (opaqueSandbox || (!inheritsOrigin && frameURL.origin !== doc.location.origin)) {
                  blocked = true;
                  continue;
                }
                const childDocument = frame.contentDocument;
                if (!childDocument) { blocked = true; continue; }
                const nested = scan(childDocument);
                if (nested.media || nested.dirty || nested.blocked) blocked = true;
              } catch (_) { blocked = true; }
            }
            return { media, dirty, blocked };
          };
          const activity = scan(document);
          return { media: activity.media || activity.blocked, dirty: activity.dirty, x: window.scrollX, y: window.scrollY };
        })()
        """
        webView.evaluateJavaScript(script) { result, error in
            DispatchQueue.main.async {
                guard error == nil,
                      let values = result as? [String: Any],
                      let media = values["media"] as? Bool,
                      let dirty = values["dirty"] as? Bool,
                      let x = values["x"] as? NSNumber,
                      let y = values["y"] as? NSNumber else {
                    completion(nil)
                    return
                }
                completion(PageSleepActivity(isPlayingMedia: media, hasUnsavedFormInput: dirty, scrollPosition: CGPoint(x: CGFloat(x.doubleValue), y: CGFloat(y.doubleValue))))
            }
        }
    }

    private func sleepConditions(in webView: WKWebView, isSelected: Bool, isPlayingMedia: Bool, hasUnsavedFormInput: Bool) -> TabSleepConditions {
        TabSleepConditions(
            isSelected: isSelected,
            isLoading: isLoading || webView.isLoading,
            hasActiveDownload: !activeDownloadObjects.isEmpty,
            isPlayingMedia: isPlayingMedia,
            isCapturingMedia: webView.cameraCaptureState != .none || webView.microphoneCaptureState != .none,
            hasUnsavedFormInput: hasUnsavedFormInput,
            hasActivePopup: hasActivePopup
        )
    }

    private func restoreSleepingWebView(_ webView: LeanWebView, url: URL) {
        guard storedWebView === webView, isSleeping else { return }
        isLoading = true
        loadingProgress = 0
        if let state = sleepingInteractionState {
            sleepingInteractionState = nil
            restoreScrollPosition = nil
            webView.interactionState = state
        } else {
            webView.load(URLRequest(url: url))
        }
        isSleeping = false
        onStateChange?()
    }

    private func releaseWebViewForSleep(_ webView: LeanWebView) {
        progressObserver?.invalidate()
        progressObserver = nil
        navigationObservers.forEach { $0.invalidate() }
        navigationObservers.removeAll()
        webView.stopLoading()
        webView.pauseAllMediaPlayback()
        webView.setAllMediaPlaybackSuspended(true)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.contextMenuHook = nil
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: PageScripts.pageReadyMessageName)
        controller.removeScriptMessageHandler(forName: PageScripts.contextMenuMessageName)
        controller.removeScriptMessageHandler(forName: PageScripts.passwordFormMessageName)
        controller.removeAllUserScripts()
        controller.removeAllContentRuleLists()
        webView.removeFromSuperview()
        storedWebView = nil
        canGoBack = false
        canGoForward = false
        isLoading = false
        loadingProgress = 0
        zoomIndicatorWorkItem?.cancel()
        isZoomIndicatorVisible = false
    }

    func captureSnapshot() {
        guard (url != nil || isPageSource), webView.bounds.width > 0 && webView.bounds.height > 0 else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 220 // The switcher displays thumbnails at 196 points wide.
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self, let image else { return }
            self.snapshot = image
        }
    }

    func updateFavicon(for specificURL: URL? = nil, explicitIconURL: String? = nil) {
        let targetURL = specificURL ?? url ?? webView.url
        guard let targetURL else {
            favicon = nil
            return
        }

        // Check cache immediately (zero latency)
        if let cached = FaviconService.shared.cachedFavicon(for: targetURL) {
            self.favicon = cached
            return
        }

        // Background load
        FaviconService.shared.loadFavicon(for: targetURL, explicitURLString: explicitIconURL) { [weak self] image in
            guard let self, let image else { return }
            self.favicon = image
        }
    }

    private func refreshState() {
        title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? webView.url?.host
            ?? "New Tab"
        if !isPageSource {
            url = webView.url
        }
        onStateChange?()
    }
}

extension LeanTab: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == PageScripts.passwordFormMessageName {
            captureSubmittedLogin(message)
            return
        }
        if message.name == PageScripts.contextMenuMessageName {
            let raw = (message.body as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty, let url = URL(string: raw) {
                lastContextLink = (url, Date())
            } else {
                lastContextLink = nil
            }
            return
        }
        guard message.name == PageScripts.pageReadyMessageName,
              message.frameInfo.isMainFrame,
              message.webView === webView else {
            return
        }
        isLoading = false
        refreshState()
    }

    private func captureSubmittedLogin(_ message: WKScriptMessage) {
        guard passwordSavePromptsEnabled,
              message.frameInfo.isMainFrame,
              message.webView === webView,
              let pageURL = webView.url,
              pageURL.scheme?.lowercased() == "https",
              let origin = PasswordVault.originURL(for: pageURL),
              let pageHost = origin.host.flatMap(PasswordVault.normalizedHost),
              let fields = message.body as? [String: Any],
              let submittedHost = (fields["host"] as? String).flatMap(PasswordVault.normalizedHost),
              submittedHost == pageHost,
              let password = fields["password"] as? String,
              !password.isEmpty, password.count <= 4096,
              let username = fields["username"] as? String,
              username.count <= 2048 else { return }
        let submittedAt = Date()
        pendingLogin = (origin, username, password, submittedAt)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            if self?.pendingLogin?.submittedAt == submittedAt { self?.pendingLogin = nil }
        }
    }
}

extension LeanTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        loadingProgress = 0
        isLoading = true
        refreshState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        refreshState()
        applyScrollbarStyle(scrollbarStyle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            if self.isLoading {
                self.isLoading = false
                self.refreshState()
            }
            self.captureSnapshot()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        loadingProgress = 1.0
        isLoading = false
        refreshState()
        applyScrollbarStyle(scrollbarStyle)

        if let position = restoreScrollPosition {
            restoreScrollPosition = nil
            webView.evaluateJavaScript("window.scrollTo(\(position.x), \(position.y))") { _, _ in }
        }

        // Extract favicon link tag from DOM if available
        let js = "document.querySelector('link[rel*=\"icon\"]') ? document.querySelector('link[rel*=\"icon\"]').href : ''"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            let explicitHref = (result as? String)?.nilIfEmpty
            self?.updateFavicon(for: webView.url, explicitIconURL: explicitHref)
        }

        offerToSavePendingPassword(after: webView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.captureSnapshot()
        }
    }

    private func offerToSavePendingPassword(after webView: WKWebView) {
        guard passwordSavePromptsEnabled,
              let pending = pendingLogin,
              Date().timeIntervalSince(pending.submittedAt) < 20,
              let pageURL = webView.url,
              pageURL.scheme?.lowercased() == "https",
              PasswordVault.originString(for: pageURL) == PasswordVault.originString(for: pending.origin) else {
            pendingLogin = nil
            return
        }
        pendingLogin = nil
        webView.evaluateJavaScript("Array.from(document.querySelectorAll('input[type=password]')).some(el => el.getClientRects().length > 0)") { [weak self, weak webView] result, error in
            guard let self, error == nil, (result as? Bool) == false,
                  let window = webView?.window else { return }
            let existing = PasswordVault.forOrigin(pending.origin)
            let isUpdate: Bool
            if case .success(let logins) = existing {
                isUpdate = logins.contains { $0.username == pending.username }
            } else {
                isUpdate = false
            }
            let alert = NSAlert()
            alert.messageText = isUpdate ? "Update saved password?" : "Save this password?"
            alert.informativeText = "Save the sign-in for \(pending.origin.host ?? pending.origin.absoluteString) in the macOS Keychain?"
            alert.alertStyle = .informational
            alert.addButton(withTitle: isUpdate ? "Update Password" : "Save Password")
            alert.addButton(withTitle: "Not Now")
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                if case .failure(let error) = PasswordVault.save(
                    origin: pending.origin,
                    username: pending.username,
                    password: pending.password
                ) {
                    self.showPasswordVaultError(error)
                }
            }
        }
    }

    private func showPasswordVaultError(_ error: PasswordVault.VaultError) {
        let alert = NSAlert()
        alert.messageText = "Password Manager"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func chooseLoginToFill(_ logins: [SavedPassword], origin: URL) {
        guard let window = webView.window,
              let originKey = PasswordVault.originString(for: origin),
              let host = origin.host else { return }
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        for login in logins {
            picker.addItem(withTitle: login.username.isEmpty ? "Unnamed account" : login.username)
        }
        let stack = NSStackView(views: [picker])
        stack.orientation = .vertical
        let alert = NSAlert()
        alert.messageText = "Fill saved sign-in"
        alert.informativeText = "Choose an account for \(host). Lean will not submit the form."
        alert.accessoryView = stack
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn,
                  let self,
                  logins.indices.contains(picker.indexOfSelectedItem),
                  self.url.flatMap(PasswordVault.originString(for:)) == originKey,
                  self.url?.scheme?.lowercased() == "https" else { return }
            let login = logins[picker.indexOfSelectedItem]
            PasswordVault.authenticate(reason: "Fill the saved sign-in for \(host)") { [weak self] authenticated in
                guard let self else { return }
                guard authenticated else {
                    self.showPasswordMessage("Lean could not authenticate you. No password was filled.")
                    return
                }
                switch PasswordVault.password(for: login) {
                case .success(let password): self.fill(login: login, password: password)
                case .failure(let error): self.showPasswordVaultError(error)
                }
            }
        }
    }

    private func showPasswordMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Password Manager"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func fill(login: SavedPassword, password: String) {
        guard url.flatMap(PasswordVault.originString(for:)) == login.origin,
              url?.scheme?.lowercased() == "https",
              let data = try? JSONSerialization.data(withJSONObject: ["username": login.username, "password": password]) else { return }
        let encodedValues = data.base64EncodedString()
        let script = """
        (() => {
          const values = JSON.parse(atob('\(encodedValues)'));
          const visible = el => el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
          const fields = Array.from(document.querySelectorAll('input[type=password]')).filter(visible);
          if (fields.length !== 1) return false;
          const password = fields[0];
          const form = password.form || document;
          const username = form.querySelector('input[autocomplete=username], input[type=email], input[name*=user i], input[name*=email i], input[name*=login i]');
          const setValue = (field, value) => {
            const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(field), 'value')?.set;
            if (setter) setter.call(field, value); else field.value = value;
            field.dispatchEvent(new Event('input', { bubbles: true }));
            field.dispatchEvent(new Event('change', { bubbles: true }));
          };
          if (username && values.username) setValue(username, values.username);
          setValue(password, values.password);
          return true;
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard error == nil, (result as? Bool) == true else {
                self?.showPasswordMessage("Lean couldn't find one unambiguous password field. The form was left untouched.")
                return
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        pendingLogin = nil
        isLoading = false
        refreshState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        pendingLogin = nil
        isLoading = false
        refreshState()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.targetFrame?.isMainFrame == true,
           let pendingLogin,
           let destination = navigationAction.request.url,
           PasswordVault.originString(for: destination) != PasswordVault.originString(for: pendingLogin.origin) {
            self.pendingLogin = nil
        }
        if let url = navigationAction.request.url,
           ExternalLinkPolicy.shouldOpenExternally(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true,
           let host = navigationAction.request.url?.host?.lowercased() {
            let wasBlocking = isBlockingEnabledForCurrentHost
            policyHost = host
            if wasBlocking != isBlockingEnabledForCurrentHost {
                rebuildUserScripts(syncRuleLists: false)
            }
            syncContentRuleLists { decisionHandler(.allow) }
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        if method == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if method == NSURLAuthenticationMethodHTTPBasic
            || method == NSURLAuthenticationMethodHTTPDigest {
            presentCredentialsSheet(for: challenge, completionHandler: completionHandler)
            return
        }
        // Let WebKit handle authentication methods this UI does not implement.
        completionHandler(.performDefaultHandling, nil)
    }

    private func presentCredentialsSheet(
        for challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let window = webView.window else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let host = challenge.protectionSpace.host
        let alert = NSAlert()
        alert.messageText = "Sign in to \(host)"
        alert.informativeText = "This site is asking for a username and password."
        alert.alertStyle = .informational
        let username = NSTextField(string: challenge.proposedCredential?.user ?? "")
        username.placeholderString = "Username"
        let password = NSSecureTextField()
        password.placeholderString = "Password"
        let stack = NSStackView(views: [username, password])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 52)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        alert.layout()
        window.makeFirstResponder(username)
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            let credential = URLCredential(
                user: username.stringValue,
                password: password.stringValue,
                persistence: .forSession
            )
            completionHandler(.useCredential, credential)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")
        if DownloadPolicy.shouldDownload(
            contentDisposition: disposition,
            mimeType: navigationResponse.response.mimeType
        ) {
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

extension LeanTab: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Some OAuth/SSO flows open a blank popup and navigate it via JS
        // after `window.open` returns. Never block the popup for a missing
        // URL: the store lets WebKit drive the load through the returned
        // web view, so a placeholder is enough here.
        let url = navigationAction.request.url ?? URL(string: "about:blank")!
        if ExternalLinkPolicy.shouldOpenExternally(url) {
            NSWorkspace.shared.open(url)
            return nil
        }
        return onOpenNewTab?(url, configuration)
    }

    /// Lets OAuth / SSO popups close themselves (`window.close()`), which
    /// previously stalled the `postMessage` handshake and left dead tabs.
    func webViewDidClose(_ webView: WKWebView) {
        onCloseTab?()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        presentAlert(message: message, showsTextField: false, isConfirmation: false) { _, _ in
            completionHandler()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        presentAlert(message: message, showsTextField: false, isConfirmation: true) { confirmed, _ in
            completionHandler(confirmed)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        presentAlert(message: prompt, showsTextField: true, isConfirmation: true, defaultText: defaultText) { confirmed, text in
            completionHandler(confirmed ? text : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        var components = URLComponents()
        components.scheme = origin.protocol
        components.host = origin.host
        components.port = origin.port == 0 ? nil : origin.port
        guard let url = components.url,
              let originKey = MediaPermissionStore.originKey(for: url) else {
            decisionHandler(.deny)
            return
        }
        let captureTypeKey: String
        let requestedMedia: String
        switch type {
        case .camera:
            captureTypeKey = "camera"
            requestedMedia = "camera"
        case .microphone:
            captureTypeKey = "microphone"
            requestedMedia = "microphone"
        case .cameraAndMicrophone:
            captureTypeKey = "cameraAndMicrophone"
            requestedMedia = "camera and microphone"
        @unknown default:
            decisionHandler(.deny)
            return
        }
        let decisionKey = "\(originKey)|\(captureTypeKey)"
        if let stored = mediaPermissionStore?.decision(forOriginKey: decisionKey) {
            decisionHandler(stored ? .grant : .deny)
            return
        }
        guard let window = webView.window else {
            decisionHandler(.deny)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Allow \(requestedMedia)?"
        alert.informativeText = "\(origin.host) wants to use your \(requestedMedia)."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        alert.alertStyle = .informational
        alert.beginSheetModal(for: window) { [weak self] response in
            let allowed = response == .alertFirstButtonReturn
            self?.mediaPermissionStore?.setDecision(allowed, forOriginKey: decisionKey)
            decisionHandler(allowed ? .grant : .deny)
        }
    }

    private func presentAlert(
        message: String,
        showsTextField: Bool,
        isConfirmation: Bool,
        defaultText: String? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let window = sheetWindow else {
            completion(false, nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = webView.title?.nilIfEmpty ?? url?.host ?? "This page"
        alert.informativeText = message
        alert.alertStyle = .informational
        let textField: NSTextField? = showsTextField ? NSTextField(string: defaultText ?? "") : nil
        if let textField {
            textField.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
            alert.accessoryView = textField
        }
        alert.addButton(withTitle: "OK")
        if isConfirmation || showsTextField {
            alert.addButton(withTitle: "Cancel")
        }
        alert.beginSheetModal(for: window) { response in
            let confirmed = response == .alertFirstButtonReturn
            completion(confirmed, textField?.stringValue)
        }
        alert.layout()
        if showsTextField {
            window.makeFirstResponder(textField)
        }
    }
}

extension LeanTab: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let manager = downloadManager
        let fallbackDir = DownloadManager.defaultDownloadsDirectory()
        try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        let destination = manager?.uniqueDestination(for: suggestedFilename)
            ?? fallbackDir.appendingPathComponent(suggestedFilename.isEmpty ? "download" : suggestedFilename)

        let totalBytes: Int64 = {
            if response.expectedContentLength > 0 { return response.expectedContentLength }
            if download.progress.totalUnitCount > 0 { return download.progress.totalUnitCount }
            return -1
        }()
        let fileName = destination.lastPathComponent
        let itemID = manager?.beginDownload(
            fileName: fileName,
            sourceURL: response.url,
            destinationURL: destination,
            totalBytes: totalBytes
        ) ?? UUID()
        let key = ObjectIdentifier(download)
        activeDownloadIDs[key] = itemID
        activeDownloadObjects[itemID] = download
        downloadLastSample[itemID] = (bytes: 0, date: Date(), speed: 0)
        downloadProgressObservers[key] = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleDownloadProgress(itemID: itemID, progress: progress)
            }
        }
        completionHandler(destination)
    }

    @MainActor
    private func handleDownloadProgress(itemID: UUID, progress: Progress) {
        let received = progress.completedUnitCount
        let total = progress.totalUnitCount
        let now = Date()
        let last = downloadLastSample[itemID]
        var speed = last?.speed ?? 0
        if let last {
            let dt = now.timeIntervalSince(last.date)
            if dt > 0.15 {
                let instant = Double(received - last.bytes) / dt
                if instant >= 0 {
                    // Exponential smoothing keeps the readout stable.
                    speed = last.speed * 0.6 + instant * 0.4
                }
                downloadLastSample[itemID] = (bytes: received, date: now, speed: speed)
            }
        } else {
            downloadLastSample[itemID] = (bytes: received, date: now, speed: 0)
        }
        downloadManager?.updateProgress(
            id: itemID,
            receivedBytes: received,
            totalBytes: total > 0 ? total : Int64(-1),
            speedBytesPerSec: speed
        )
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        let itemID = activeDownloadIDs[key]
        downloadProgressObservers[key]?.invalidate()
        downloadProgressObservers[key] = nil
        activeDownloadIDs[key] = nil
        guard let itemID else { return }
        activeDownloadObjects[itemID] = nil
        // Final byte count from disk beats progress accounting.
        if let item = downloadManager?.downloads.first(where: { $0.id == itemID }) {
            let diskSize = (try? FileManager.default.attributesOfItem(atPath: item.destinationURL.path)[.size] as? Int64) ?? nil
            let received = diskSize ?? download.progress.completedUnitCount
            let total = download.progress.totalUnitCount > 0 ? download.progress.totalUnitCount : received
            downloadManager?.updateProgress(id: itemID, receivedBytes: received, totalBytes: total, speedBytesPerSec: 0)
        }
        let fileName = downloadManager?.downloads.first(where: { $0.id == itemID })?.destinationURL.lastPathComponent
        downloadManager?.finishDownload(id: itemID, fileName: fileName)
        downloadLastSample[itemID] = nil
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        let key = ObjectIdentifier(download)
        let itemID = activeDownloadIDs[key]
        downloadProgressObservers[key]?.invalidate()
        downloadProgressObservers[key] = nil
        activeDownloadIDs[key] = nil
        guard let itemID else { return }
        activeDownloadObjects[itemID] = nil
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        downloadManager?.failDownload(id: itemID, errorDescription: error.localizedDescription, cancelled: cancelled)
        downloadLastSample[itemID] = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
