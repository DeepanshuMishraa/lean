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
    @Published private(set) var savedPasswordSuggestions: [SavedPassword] = []
    @Published private(set) var passwordSuggestionFrame: CGRect?
    @Published var snapshot: NSImage? = nil
    @Published var favicon: NSImage? = nil
    @Published var isPinned: Bool = false
    @Published var isPlayingMedia: Bool = false
    @Published var isMuted: Bool = false
    /// The colour the page has declared for its own chrome, with
    /// `<meta name="theme-color">` or the CSS `theme-color` media feature —
    /// straight from WebKit, which already tracks it. Nil for a page that
    /// hasn't declared one, or hasn't loaded yet.
    @Published private(set) var themeColor: NSColor?
    /// A failed main-frame navigation, shown as an error page instead of a
    /// blank tab. Set on failure, cleared when the next navigation starts,
    /// commits, or finishes.
    @Published var pageError: PageLoadError?
    /// The main-frame address the current navigation is headed to. Matches
    /// failures to the page (not subframes) in didFail/didFailProvisional.
    private var pendingMainFrameURL: URL?
    /// The https address already retried over plain http (see
    /// tryHTTPFallback). One retry per navigation — a second failure shows
    /// the error page instead of looping.
    private var httpFallbackAttemptedFor: String?
    private var mainDocumentMIMEType: String?
    /// Last heartbeat per frame. Playing frames report every poll; a frame
    /// that played briefly and then detached (ad iframe, SPA swap) can never
    /// send its goodbye, so frames unheard from past the timeout are evicted
    /// instead of holding the music icon on forever.
    private var mediaPlayingFrames: [String: Date] = [:]
    private var mediaPruneTimer: Timer?
    /// One renderer process pool shared by every non-popup tab. A fresh
    /// `WKWebViewConfiguration()` gets a fresh pool, so without this N tabs
    /// means N renderer processes (memory + CPU). Popups keep the opener's
    /// configuration (and pool) for OAuth/SSO state.
    private static let sharedProcessPool = WKProcessPool()
    /// Last published progress + timestamp. `estimatedProgress` KVO fires
    /// dozens of times per second; publishing every tick re-renders the
    /// whole tab strip. Only publish meaningful deltas.
    private var lastPublishedProgress: Double = -1
    private var lastProgressPublishDate = Date.distantPast

    deinit {
        mediaPruneTimer?.invalidate()
    }

    // MARK: - Split Tab Support
    @Published var splitTabs: [LeanTab] = []
    @Published var activeSplitIndex: Int = 0
    @Published var splitWidthRatios: [CGFloat] = []

    var isSplit: Bool { splitTabs.count > 1 }

    var activeTab: LeanTab {
        if isSplit && activeSplitIndex >= 0 && activeSplitIndex < splitTabs.count {
            return splitTabs[activeSplitIndex]
        }
        return self
    }

    private(set) var scrollbarStyle: ScrollbarStyle
    private(set) var pageFont: LeanFont
    private(set) var pageHeadingWeight: Int
    private(set) var pageBodyWeight: Int
    private(set) var adBlockingEnabled: Bool
    private(set) var adBlockingExcludedHosts: Set<String>
    private(set) var passwordSavePromptsEnabled: Bool
    private(set) var passwordSuggestionsEnabled: Bool
    private(set) var passkeysEnabled: Bool
    private let passkeyRelay = PasskeyRelay()
    private var pendingLogin: (origin: URL, username: String, password: String, submittedAt: Date)?
    private var restoreScrollPosition: CGPoint?
    private var policyHost: String?
    /// Whether the compiled rule lists are currently attached to this tab's
    /// configuration. Decided navigations gate on it only when it is false
    /// or the blocking state just changed; otherwise the attached set
    /// already matches and answering immediately costs no correctness.
    private var contentRuleListsInstalled = false

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
    /// Shift-clicked link, for a peek over the page. Set by the store.
    var onPeekLink: ((URL) -> Void)?
    /// A download that failed on its own (not cancelled). Set by the store.
    var onDownloadFailed: (() -> Void)?
    /// Peek tabs live outside the row: links inside one just go.
    var isPeekTab = false
    /// Shift-click peeks at links when Settings says so. Set by the store.
    var peeksLinks = false
    var downloadManager: DownloadManager?
    var mediaPermissionStore: MediaPermissionStore?
    private var progressObserver: NSKeyValueObservation?
    private var navigationObservers: [NSKeyValueObservation] = []
    private var activeDownloadIDs: [ObjectIdentifier: UUID] = [:]
    private var downloadProgressObservers: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var downloadLastSample: [UUID: (bytes: Int64, date: Date, speed: Double)] = [:]
    private var activeDownloadObjects: [UUID: WKDownload] = [:]
    /// Downloads seen via `didBecome download:` but not yet assigned a
    /// destination. Retained here (mirroring Search's `downloading` array)
    /// so the `WKDownload` — whose delegate is weak — survives until
    /// `decideDestinationUsing` runs, and so the tab counts as busy.
    private var retainedDownloads: [WKDownload] = []
    /// Item IDs with a completion watchdog armed (see
    /// scheduleDownloadFinalizeWatchdog). Removed when the download ends
    /// for real, so the watchdog can only fire while one is still active.
    private var downloadWatchdogs: Set<UUID> = []
    private var zoomIndicatorWorkItem: DispatchWorkItem?
    private var passwordSuggestionHideWorkItem: DispatchWorkItem?

    func cancelActiveDownload(id: UUID) {
        if let download = activeDownloadObjects[id] {
            forget(download)
            download.cancel()
        }
        activeDownloadObjects[id] = nil
        downloadWatchdogs.remove(id)
    }

    /// Every download this tab has going, heard from until it ends — and
    /// counted, so a tab still sending one to disk is never put to sleep.
    private func keep(_ download: WKDownload) {
        download.delegate = self
        if !retainedDownloads.contains(where: { $0 === download }) {
            retainedDownloads.append(download)
        }
    }

    private func forget(_ download: WKDownload) {
        retainedDownloads.removeAll(where: { $0 === download })
    }

    init(
        dataStore: WKWebsiteDataStore,
        initialURL: URL?,
        isDark: Bool = false,
        scrollbarStyle: ScrollbarStyle = .normal,
        pageFont: LeanFont = .system,
        pageHeadingWeight: Int = 0,
        pageBodyWeight: Int = 0,
        adBlockingEnabled: Bool = true,
        adBlockingExcludedHosts: Set<String> = [],
        passwordSavePromptsEnabled: Bool = true,
        passwordSuggestionsEnabled: Bool = true,
        passkeysEnabled: Bool = true,
        configuration: WKWebViewConfiguration? = nil
    ) {
        self.dataStore = dataStore
        if let configuration {
            let popupConfig = (configuration.copy() as? WKWebViewConfiguration) ?? configuration
            popupConfig.userContentController = WKUserContentController()
            self.initialConfiguration = popupConfig
        } else {
            self.initialConfiguration = nil
        }
        self.isDark = isDark
        self.scrollbarStyle = scrollbarStyle
        self.pageFont = pageFont
        self.pageHeadingWeight = pageHeadingWeight
        self.pageBodyWeight = pageBodyWeight
        self.adBlockingEnabled = adBlockingEnabled
        self.adBlockingExcludedHosts = adBlockingExcludedHosts
        self.passwordSavePromptsEnabled = passwordSavePromptsEnabled
        self.passwordSuggestionsEnabled = passwordSuggestionsEnabled
        self.passkeysEnabled = passkeysEnabled
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
        // A fresh configuration has nothing attached yet.
        contentRuleListsInstalled = false
        // The popup configuration was sanitized in init, but keeping the
        // configuration preserves its process pool for shared OAuth/SSO state.
        // Non-popup tabs share one process pool: fewer renderer processes,
        // less memory, less CPU. Sleep/wake reuses the pool instead of
        // spawning a new process per cycle.
        let effectiveConfiguration = initialConfiguration ?? WKWebViewConfiguration()
        let configuration = effectiveConfiguration
        if initialConfiguration == nil {
            configuration.processPool = Self.sharedProcessPool
        }
        configuration.websiteDataStore = dataStore
        if #available(macOS 15.4, *) {
            configuration.webExtensionController = BrowserExtensionManager.shared.controller
        }
        configuration.preferences.isElementFullscreenEnabled = true
        // WebKit's "developer extras": Inspect Element in a page's
        // right-click menu, and the Web Inspector the View menu opens.
        WebInspector.enableDeveloperExtras(configuration.preferences)
        // 120 Hz pages, when Settings asks: WebKit reads the flag as the
        // page is made, so this has to happen before the view exists.
        FrameRate.apply(to: configuration.preferences)

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
        configuration.userContentController.addUserScript(
            WKUserScript(source: PageScripts.mediaStateTracker, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        addPasswordCaptureScript(to: configuration.userContentController)
        addPasswordSuggestionScript(to: configuration.userContentController)
        addPasskeyScripts(to: configuration.userContentController)
        configuration.userContentController.addUserScript(
            WKUserScript(source: PageScripts.middleClickClosePage, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )

        let webView = LeanWebView(frame: .zero, configuration: configuration)
        storedWebView = webView
        webView.configuration.userContentController.add(self, name: PageScripts.pageReadyMessageName)
        webView.configuration.userContentController.add(self, name: PageScripts.contextMenuMessageName)
        webView.configuration.userContentController.add(self, name: PageScripts.passwordFormMessageName)
        webView.configuration.userContentController.add(self, name: PageScripts.passwordFieldMessageName)
        webView.configuration.userContentController.add(self, name: PageScripts.middleClickMessageName)
        webView.configuration.userContentController.add(self, name: PageScripts.mediaStateMessageName)
        addPasskeyHandler(to: webView.configuration.userContentController)
        webView.contextMenuHook = { [weak self] menu in
            self?.appendPageMenuItems(to: menu)
        }
        // Layer-backed for stage hosting. Never asynchronous: async layer
        // backing on a WKWebView forces offscreen compositing and is what
        // made scrolling jank (Search sets neither flag on its pages).
        webView.wantsLayer = true
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = isDark ? NSColor.black : NSColor.white
        }

        // Standard Desktop Safari User-Agent ensures YouTube, Google, Twitter, etc. send full desktop content
        let defaultSafariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        webView.customUserAgent = defaultSafariUA

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configureScrolling()
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
                // Throttle: publish at most ~10Hz or on meaningful deltas.
                // Every publish re-renders every view observing the tab.
                let now = Date()
                let delta = abs(progress - self.lastPublishedProgress)
                let isComplete = progress >= 1.0
                guard isComplete || delta >= 0.02 || now.timeIntervalSince(self.lastProgressPublishDate) >= 0.1 else { return }
                self.lastPublishedProgress = progress
                self.lastProgressPublishDate = now
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
            },
            webView.observe(\.themeColor, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    // SPA header repaints fire this often; only publish real
                    // changes so the strip doesn't re-render underneath tabs.
                    let newColor = webView.themeColor
                    let changed: Bool = {
                        switch (self.themeColor, newColor) {
                        case (nil, nil): return false
                        case (nil, _), (_, nil): return true
                        case (let old?, let new?): return !old.isEqual(new)
                        }
                    }()
                    guard changed else { return }
                    self.themeColor = newColor
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
            self.contentRuleListsInstalled = true
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

    private func addPasswordSuggestionScript(to controller: WKUserContentController) {
        guard passwordSuggestionsEnabled else { return }
        controller.addUserScript(
            WKUserScript(source: PageScripts.passwordFieldFocus, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
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

    /// Passkey patch in the page's own world (it replaces the page's
    /// functions) plus the bridge in Lean's own world that carries requests
    /// to the reply handler — off or on, so a build without the entitlement
    /// still steers sites to passwords instead of stranding them.
    private func addPasskeyScripts(to controller: WKUserContentController) {
        if passkeysEnabled {
            controller.addUserScript(
                WKUserScript(source: PasskeyRelay.page, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
            )
        } else {
            controller.addUserScript(
                WKUserScript(source: PasskeyRelay.withoutPasskeys, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
            )
        }
        controller.addUserScript(
            WKUserScript(source: PasskeyRelay.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: LeanWeb.world)
        )
    }

    private func addPasskeyHandler(to controller: WKUserContentController) {
        // Registering a name twice is a hard crash, so clear before claiming.
        removePasskeyHandler(from: controller)
        controller.addScriptMessageHandler(passkeyRelay, contentWorld: LeanWeb.world, name: PasskeyRelay.name)
    }

    private func removePasskeyHandler(from controller: WKUserContentController) {
        // A popup inherits its opener's configuration, handlers included,
        // and registering a name twice is a hard crash — so clear both
        // worlds before claiming, and on teardown.
        controller.removeScriptMessageHandler(forName: PasskeyRelay.name, contentWorld: LeanWeb.world)
        controller.removeScriptMessageHandler(forName: PasskeyRelay.name, contentWorld: .page)
    }

    func applyPasskeysPreferences(enabled: Bool) {
        guard passkeysEnabled != enabled else { return }
        passkeysEnabled = enabled
        guard storedWebView != nil else { return }
        rebuildUserScripts()
        // User scripts only run at document start, so a live page would
        // keep answering with the old patch until its next navigation.
        // Reload tabs showing a committed web page — the same tradeoff as
        // toggling blocking for a host. Settings, source, and empty tabs
        // have no page API to update and are left alone.
        if url != nil, !isSettingsPage, !isPageSource {
            reload()
        }
    }

    func applyPasswordPreferences(savePromptsEnabled: Bool, suggestionsEnabled: Bool) {
        let promptsChanged = passwordSavePromptsEnabled != savePromptsEnabled
        let suggestionsChanged = passwordSuggestionsEnabled != suggestionsEnabled
        passwordSavePromptsEnabled = savePromptsEnabled
        passwordSuggestionsEnabled = suggestionsEnabled
        if !savePromptsEnabled { pendingLogin = nil }
        if !suggestionsEnabled { hidePasswordSuggestions() }
        if (promptsChanged || suggestionsChanged), storedWebView != nil {
            rebuildUserScripts()
        }
        if suggestionsChanged, suggestionsEnabled {
            storedWebView?.evaluateJavaScript(PageScripts.passwordFieldFocus, completionHandler: nil)
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
        webView.configuration.userContentController.addUserScript(
            WKUserScript(source: PageScripts.mediaStateTracker, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        addPasswordCaptureScript(to: webView.configuration.userContentController)
        addPasswordSuggestionScript(to: webView.configuration.userContentController)
        addPasskeyScripts(to: webView.configuration.userContentController)
        webView.configuration.userContentController.addUserScript(
            WKUserScript(source: PageScripts.middleClickClosePage, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )

        if syncRuleLists { syncContentRuleLists() }
    }

    func applyScrollbarStyle(_ style: ScrollbarStyle) {
        self.scrollbarStyle = style
        guard let webView = storedWebView else { return }
        rebuildUserScripts()
        let script = PageScripts.scrollbar(style)
        webView.evaluateJavaScript(script) { _, _ in }
    }

    /// Re-apply the 120 Hz preference to an already-made page. WebKit reads
    /// the flag as the page is made, so a new tab is sure to follow only
    /// once reloaded; going up, it often takes at the next switch to it.
    func applyHighFrameRate() {
        guard let webView = storedWebView else { return }
        FrameRate.apply(to: webView.configuration.preferences)
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

    func load(_ url: URL, isHTTPFallbackRetry: Bool = false) {
        pendingNavigationID = UUID()
        let navigationID = pendingNavigationID
        if !isHTTPFallbackRetry {
            httpFallbackAttemptedFor = nil
        }
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
        pageError = nil
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

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        guard let webView = storedWebView else { return }
        let sel = NSSelectorFromString("_setPageMuted:")
        typealias SetMutedFunc = @convention(c) (AnyObject, Selector, UInt32) -> Void
        if webView.responds(to: sel), let method = webView.method(for: sel) {
            let imp = unsafeBitCast(method, to: SetMutedFunc.self)
            imp(webView, sel, muted ? 1 : 0)
        }
        let script = """
        (function() {
            try {
                var media = document.querySelectorAll('audio, video');
                for (var i = 0; i < media.length; i++) {
                    media[i].muted = \(muted ? "true" : "false");
                }
            } catch(e) {}
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - Page context menu

    /// Latest link and media under a right-click, reported by the injected tracker.
    private var lastContextLink: (url: URL, at: Date)?
    private var lastContextMedia: (url: URL, kind: String, at: Date)?

    private var freshContextLinkURL: URL? {
        guard let last = lastContextLink, Date().timeIntervalSince(last.at) < 2 else { return nil }
        return last.url
    }

    private var freshContextMedia: (url: URL, kind: String)? {
        guard let last = lastContextMedia, Date().timeIntervalSince(last.at) < 2 else { return nil }
        return (last.url, last.kind)
    }

    private func appendPageMenuItems(to menu: NSMenu) {
        // Our items all target self; WebKit's don't. Strip ours first so a
        // reused menu object never accumulates duplicates across opens.
        menu.items
            .filter { $0.target === self }
            .forEach { menu.removeItem($0) }

        // WebKit's image/video download actions bypass WKNavigationDelegate
        // on some sites. Retarget those items to the same WKDownload pipeline
        // used by ordinary downloads. Standalone media documents do not expose
        // a page element to our script, so their tab URL is the media URL.
        let media = freshContextMedia
        let directKind = mainDocumentMIMEType?.hasPrefix("video/") == true
            ? "video"
            : (mainDocumentMIMEType?.hasPrefix("image/") == true ? "image" : nil)
        let contextKind = media?.kind ?? directKind
        let contextURL = media?.url ?? (directKind == nil ? nil : webView.url)
        var patchedMediaItem = false
        for item in menu.items {
            let title = item.title.lowercased()
            guard title.contains("download") || title.contains("save") else { continue }
            let itemKind = title.contains("video") ? "video" : (title.contains("image") ? "image" : nil)
            guard itemKind == contextKind, let contextURL else { continue }
            item.target = self
            item.action = #selector(pageMenuDownloadMedia(_:))
            item.representedObject = contextURL.absoluteString
            patchedMediaItem = true
        }
        if !patchedMediaItem, let contextKind, let contextURL {
            let download = NSMenuItem(
                title: contextKind == "video" ? "Download Video" : "Download Image",
                action: #selector(pageMenuDownloadMedia(_:)),
                keyEquivalent: ""
            )
            download.target = self
            download.representedObject = contextURL.absoluteString
            menu.addItem(download)
        }

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
           let menuScheme = currentURL.scheme?.lowercased(),
           menuScheme == "https" || menuScheme == "http",
           currentURL.host != nil,
           case .success(let logins) = PasswordVault.forSite(currentURL),
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
        // WebKit's own first item reads Stop while the page loads and Reload
        // once it settles; this one reloads unconditionally.
        let reloadItem = NSMenuItem(title: "Reload", action: #selector(pageMenuReload), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)
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
    @objc private func pageMenuReload() { reload() }

    @objc private func pageMenuDownloadMedia(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let url = URL(string: raw) else { return }
        downloadContextMedia(at: url)
    }

    func downloadContextMedia(at url: URL) {
        switch url.scheme?.lowercased() {
        case "http", "https":
            webView.startDownload(using: URLRequest(url: url)) { [weak self] download in
                self?.keep(download)
            }
        case "blob":
            guard let data = try? JSONEncoder().encode(url.absoluteString),
                  let urlLiteral = String(data: data, encoding: .utf8) else { return }
            let script = """
            (() => {
                const link = document.createElement('a');
                link.href = \(urlLiteral);
                link.download = 'video.mp4';
                document.body.appendChild(link);
                link.click();
                link.remove();
            })();
            """
            webView.evaluateJavaScript(script) { [weak self] _, error in
                if error != nil { self?.onDownloadFailed?() }
            }
        default:
            break
        }
    }

    @objc private func pageMenuFillSavedPassword() {
        guard passwordSuggestionsEnabled,
              let origin = url,
              let fillScheme = origin.scheme?.lowercased(),
              fillScheme == "https" || fillScheme == "http",
              case .success(let logins) = PasswordVault.forSite(origin),
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
        for sub in splitTabs where sub.id != self.id {
            sub.destroy()
        }
        splitTabs.removeAll()
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
        onPeekLink = nil
        onDownloadFailed = nil
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: PageScripts.passwordFieldMessageName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: PageScripts.middleClickMessageName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: PageScripts.mediaStateMessageName)
        removePasskeyHandler(from: webView.configuration.userContentController)
        webView.configuration.userContentController.removeAllUserScripts()
        zoomIndicatorWorkItem?.cancel()
        hidePasswordSuggestions()
        webView.removeFromSuperview()
        mediaPruneTimer?.invalidate()
        mediaPruneTimer = nil
        for (key, observation) in downloadProgressObservers {
            observation.invalidate()
            _ = key
        }
        downloadProgressObservers.removeAll()
        retainedDownloads.removeAll()
        activeDownloadObjects.removeAll()
        storedWebView = nil
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
            hasActiveDownload: !activeDownloadObjects.isEmpty || !retainedDownloads.isEmpty,
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
        mediaPruneTimer?.invalidate()
        mediaPruneTimer = nil
        webView.stopLoading()
        webView.pauseAllMediaPlayback()
        webView.setAllMediaPlaybackSuspended(true)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.contextMenuHook = nil
        let controller = webView.configuration.userContentController
        // Must mirror destroy(): the controller retains handlers strongly,
        // so any leftover name leaks the whole web view + config + scripts.
        controller.removeScriptMessageHandler(forName: PageScripts.pageReadyMessageName)
        controller.removeScriptMessageHandler(forName: PageScripts.contextMenuMessageName)
        controller.removeScriptMessageHandler(forName: PageScripts.passwordFormMessageName)
        controller.removeScriptMessageHandler(forName: PageScripts.passwordFieldMessageName)
        controller.removeScriptMessageHandler(forName: PageScripts.middleClickMessageName)
        controller.removeScriptMessageHandler(forName: PageScripts.mediaStateMessageName)
        removePasskeyHandler(from: controller)
        controller.removeAllUserScripts()
        controller.removeAllContentRuleLists()
        contentRuleListsInstalled = false
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

        // Check cache immediately (zero latency), keyed like the loader so
        // an explicit page icon never reads another icon's cached result.
        if let cached = FaviconService.shared.cachedFavicon(for: targetURL, explicitURLString: explicitIconURL) {
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
            ?? pageError?.url?.host
            ?? url?.host
            ?? "New Tab"
        if !isPageSource {
            // After a failed navigation WebKit committed nothing, so
            // webView.url is nil — but the attempted address must stay on
            // the tab (omnibar, reload, session restore). History still
            // skips it: the store never records while pageError is set.
            url = webView.url ?? pageError?.url
        }
        onStateChange?()
    }
}

extension LeanTab: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == PageScripts.middleClickMessageName {
            guard message.webView === webView else { return }
            onCloseTab?()
            return
        }
        if message.name == PageScripts.passwordFieldMessageName {
            updatePasswordSuggestions(message)
            return
        }
        if message.name == PageScripts.passwordFormMessageName {
            captureSubmittedLogin(message)
            return
        }
        if message.name == PageScripts.contextMenuMessageName {
            let body = message.body as? [String: Any]
            let link = (body?["link"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let mediaURL = (body?["mediaURL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let mediaKind = body?["mediaKind"] as? String ?? ""
            lastContextLink = link.isEmpty ? nil : URL(string: link).map { ($0, Date()) }
            lastContextMedia = mediaURL.isEmpty ? nil : URL(string: mediaURL).map { ($0, mediaKind, Date()) }
            return
        }
        if message.name == PageScripts.mediaStateMessageName {
            guard message.webView === storedWebView else { return }
            if let dict = message.body as? [String: Any],
               let frameId = dict["id"] as? String,
               let playing = dict["isPlaying"] as? Bool {
                if playing {
                    mediaPlayingFrames[frameId] = Date()
                    scheduleMediaPrune()
                } else {
                    mediaPlayingFrames.removeValue(forKey: frameId)
                }
                refreshMediaState()
                if let muted = dict["isMuted"] as? Bool, isPlayingMedia, muted != self.isMuted {
                    self.isMuted = muted
                }
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

    private func refreshMediaState() {
        pruneSilentMediaFrames()
        let anyPlaying = !mediaPlayingFrames.isEmpty
        if self.isPlayingMedia != anyPlaying {
            self.isPlayingMedia = anyPlaying
        }
    }

    /// Playing frames heartbeat every poll (1.5s); evict frames unheard
    /// from for twice that plus margin, so a detached frame cannot wedge
    /// the indicator on. Runs only while something claims to play.
    private func scheduleMediaPrune() {
        guard mediaPruneTimer == nil, !mediaPlayingFrames.isEmpty else { return }
        mediaPruneTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pruneSilentMediaFrames()
                let anyPlaying = !self.mediaPlayingFrames.isEmpty
                if self.isPlayingMedia != anyPlaying {
                    self.isPlayingMedia = anyPlaying
                }
                if self.mediaPlayingFrames.isEmpty {
                    self.mediaPruneTimer?.invalidate()
                    self.mediaPruneTimer = nil
                }
            }
        }
    }

    private func pruneSilentMediaFrames() {
        let cutoff = Date().addingTimeInterval(-4.0)
        mediaPlayingFrames = mediaPlayingFrames.filter { $0.value > cutoff }
    }

    private func updatePasswordSuggestions(_ message: WKScriptMessage) {
        guard passwordSuggestionsEnabled, message.frameInfo.isMainFrame,
              message.webView === webView,
              let fields = message.body as? [String: Any],
              let rect = fields["rect"] as? [String: Double],
              let x = rect["x"], let y = rect["y"],
              let width = rect["width"], let height = rect["height"] else {
            if passwordSuggestionFrame != nil { schedulePasswordSuggestionsHide() }
            return
        }
        guard let origin = url ?? webView.url,
              let scheme = origin.scheme?.lowercased(), scheme == "https" || scheme == "http",
              case .success(let logins) = PasswordVault.forSite(origin),
              !logins.isEmpty else {
            if passwordSuggestionFrame != nil { schedulePasswordSuggestionsHide() }
            return
        }
        passwordSuggestionHideWorkItem?.cancel()
        savedPasswordSuggestions = logins
        passwordSuggestionFrame = CGRect(x: x, y: y, width: width, height: height).applying(
            CGAffineTransform(scaleX: pageZoom, y: pageZoom)
        )
    }

    private func schedulePasswordSuggestionsHide() {
        passwordSuggestionHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hidePasswordSuggestions() }
        passwordSuggestionHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func hidePasswordSuggestions() {
        passwordSuggestionHideWorkItem?.cancel()
        passwordSuggestionHideWorkItem = nil
        passwordSuggestionFrame = nil
        savedPasswordSuggestions = []
    }

    /// Whether a page may use a saved login: same registrable domain, so a
    /// password kept for example.com also fills accounts.example.com — and
    /// the same scheme, so an http page never spends what was kept from https.
    /// Filling still requires Touch ID on every use.
    private static func isSameSite(_ page: URL, _ login: SavedPassword) -> Bool {
        guard let scheme = page.scheme?.lowercased(), scheme == login.scheme,
              let host = page.host?.lowercased(),
              let loginHost = PasswordVault.normalizedHost(login.host) else { return false }
        return PasswordVault.registrableHost(host) == PasswordVault.registrableHost(loginHost)
    }

    func fillSavedPassword(_ login: SavedPassword) {
        guard passwordSuggestionsEnabled,
              let origin = url,
              let scheme = origin.scheme?.lowercased(), scheme == "https" || scheme == "http",
              Self.isSameSite(origin, login),
              let host = origin.host else { return }
        hidePasswordSuggestions()
        PasswordVault.authenticate(reason: "Fill the saved sign-in for \(host)") { [weak self] authenticated in
            guard let self, authenticated,
                  let current = self.url, Self.isSameSite(current, login) else { return }
            PasswordVault.touch(login)
            switch PasswordVault.password(for: login) {
            case .success(let password): self.fill(login: login, password: password)
            case .failure(let error): self.showPasswordVaultError(error)
            }
        }
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
        lastPublishedProgress = 0
        lastProgressPublishDate = Date()
        loadingProgress = 0
        isLoading = true
        pageError = nil
        mediaPlayingFrames.removeAll()
        isPlayingMedia = false
        refreshState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        pageError = nil
        pendingMainFrameURL = nil
        refreshState()
        // No script rebuild here: the 12 user scripts registered at
        // createWebView persist per-configuration and already cover new
        // navigations. Rebuilding twice per load (commit+finish) was pure
        // waste (removeAll+re-add x12 + live JS eval, per navigation).
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
        lastPublishedProgress = 1.0
        isLoading = false
        pageError = nil
        pendingMainFrameURL = nil
        refreshState()

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
            let existing = PasswordVault.forSite(pending.origin)
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
              let originHost = origin.host?.lowercased(),
              let host = origin.host else { return }
        let originSite = PasswordVault.registrableHost(originHost)
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
                  let currentHost = self.url?.host?.lowercased(),
                  PasswordVault.registrableHost(currentHost) == originSite,
                  let pickerScheme = self.url?.scheme?.lowercased(),
                  pickerScheme == "https" || pickerScheme == "http" else { return }
            let login = logins[picker.indexOfSelectedItem]
            PasswordVault.authenticate(reason: "Fill the saved sign-in for \(host)") { [weak self] authenticated in
                guard let self else { return }
                guard authenticated else {
                    self.showPasswordMessage("Lean could not authenticate you. No password was filled.")
                    return
                }
                PasswordVault.touch(login)
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
        guard let page = url, Self.isSameSite(page, login),
              let fillScheme = url?.scheme?.lowercased(),
              fillScheme == "https" || fillScheme == "http",
              let data = try? JSONSerialization.data(withJSONObject: ["username": login.username, "password": password]) else { return }
        let encodedValues = data.base64EncodedString()
        let script = """
        (() => {
          const values = JSON.parse(atob('\(encodedValues)'));
          const visible = el => el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
          const fields = Array.from(document.querySelectorAll('input[type=password]')).filter(visible);
          const password = fields[0];
          const scope = (password && password.form) || (document.activeElement && document.activeElement.form) || document;
          const formScope = (password && password.form) || (password && password.closest('form')) || scope;
          let username = null;
          if (password) {
            for (const field of formScope.querySelectorAll('input')) {
              if (field === password) break;
              if (/^(text|email|tel)$/i.test(field.type || 'text')) username = field;
            }
          }
          const setValue = (field, value) => {
            const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
            if (setter && setter.set) setter.set.call(field, value); else field.value = value;
            field.dispatchEvent(new Event('input', { bubbles: true }));
            field.dispatchEvent(new Event('change', { bubbles: true }));
          };
          if (!password) {
            if (!username || !values.username) return false;
            setValue(username, values.username);
            username.focus();
            return true;
          }
          if (username && values.username) setValue(username, values.username);
          setValue(password, values.password);
          return true;
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard error == nil, (result as? Bool) == true else {
                self?.showPasswordMessage("Lean couldn't find the matching sign-in fields. The form was left untouched.")
                return
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        if tryHTTPFallback(for: error) { return }
        pendingLogin = nil
        isLoading = false
        recordPageErrorIfMainFrame(error)
        // Always refresh: recording the error alone publishes to nobody —
        // the content card watches the store, not the tab — so without
        // this the error page waits for the next tab switch to appear.
        refreshState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        if tryHTTPFallback(for: error) { return }
        pendingLogin = nil
        isLoading = false
        recordPageErrorIfMainFrame(error)
        // Same as above: the error page must appear at once, not on the
        // next redraw. refreshState keeps the attempted address for a
        // fresh tab out of history (nothing committed to record).
        refreshState()
    }

    /// Show an error page for a failed main-frame navigation; stay silent
    /// for subframes, cancellations, and loads WebKit interrupted itself.
    private func recordPageErrorIfMainFrame(_ error: Error) {
        let failing = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
        guard let failing,
              failing == pendingMainFrameURL || (pendingMainFrameURL == nil && failing == url),
              let pageError = PageLoadError.from(error, for: failing) else { return }
        pendingMainFrameURL = nil
        self.pageError = pageError
    }

    /// Failures that mean "nothing speaks TLS here": refused, timed out,
    /// dropped mid-handshake, or the handshake/cert itself failed. DNS
    /// misses are excluded — plain http would not save those.
    private static let httpFallbackErrorCodes: Set<Int> = [
        NSURLErrorCannotConnectToHost,
        NSURLErrorTimedOut,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorSecureConnectionFailed,
        NSURLErrorServerCertificateHasBadDate,
        NSURLErrorServerCertificateUntrusted,
        NSURLErrorServerCertificateHasUnknownRoot,
        NSURLErrorServerCertificateNotYetValid,
    ]

    /// Retry a failed https main-frame navigation over plain http when the
    /// host is a LAN box, dev server, or IP literal — those are usually
    /// http-only, and the https attempt dies before any bytes flow. True
    /// when the retry started (callers must skip the error page then).
    private func tryHTTPFallback(for error: Error) -> Bool {
        let ns = error as NSError
        guard Self.httpFallbackErrorCodes.contains(ns.code) else { return false }
        guard let failing = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
              failing == pendingMainFrameURL || (pendingMainFrameURL == nil && failing == url),
              failing.scheme?.lowercased() == "https",
              let host = failing.host,
              httpFallbackAttemptedFor != failing.absoluteString,
              AddressResolver.isLocalHost(host) || AddressResolver.isIPv4Literal(host),
              var components = URLComponents(url: failing, resolvingAgainstBaseURL: false)
        else { return false }
        components.scheme = "http"
        // An explicit :443 belongs to the https attempt, not the server.
        if components.port == 443 { components.port = nil }
        guard let httpURL = components.url else { return false }
        httpFallbackAttemptedFor = failing.absoluteString
        pendingMainFrameURL = nil
        pageError = nil
        load(httpURL, isHTTPFallbackRetry: true)
        return true
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // "Download Image", "Download Linked File" from the page's own
        // context menu, and a link with the `download` attribute all arrive
        // as an ordinary-looking action with this one flag set. Answered
        // with `.allow`, WebKit tries to load it as the next page — nowhere
        // for that to go, so nothing happens and nothing says why.
        // `.download` turns it into the `WKDownload` below.
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
           navigationAction.targetFrame?.isMainFrame == true {
            pendingMainFrameURL = url
        }
        guard !navigationAction.shouldPerformDownload else {
            decisionHandler(.download)
            return
        }
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
        // Shift-click, when Settings says so: a peek at the link, over this
        // page (see PeekPanel). Only from a tab in the row — within a peek,
        // a link just goes.
        if peeksLinks, !isPeekTab,
           navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
           navigationAction.modifierFlags.intersection([.shift, .command, .option, .control]) == .shift {
            decisionHandler(.cancel)
            onPeekLink?(url)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true,
           let host = navigationAction.request.url?.host?.lowercased() {
            let wasBlocking = isBlockingEnabledForCurrentHost
            policyHost = host
            let blockingChanged = wasBlocking != isBlockingEnabledForCurrentHost
            if blockingChanged {
                rebuildUserScripts(syncRuleLists: false)
            }
            if blockingChanged || !contentRuleListsInstalled {
                // This navigation's filtering depends on lists not yet
                // installed: wait for them, then allow, or the click loads
                // unfiltered. Otherwise the attached set already matches,
                // so answer at once instead of stalling behind a cold
                // rule-list compile; sync anyway for drift.
                syncContentRuleLists { decisionHandler(.allow) }
                return
            }
            decisionHandler(.allow)
            syncContentRuleLists()
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
        if navigationResponse.isForMainFrame {
            mainDocumentMIMEType = navigationResponse.response.mimeType?.lowercased()
        }
        // A redirect (3xx) has no content of its own and must be followed
        // rather than downloaded — even when its headers claim a binary
        // MIME type, as some servers do on their redirects.
        if let http = navigationResponse.response as? HTTPURLResponse,
           (300...399).contains(http.statusCode) {
            decisionHandler(.allow)
            return
        }
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")
        if DownloadPolicy.shouldDownload(
            contentDisposition: disposition,
            mimeType: navigationResponse.response.mimeType,
            canShowMIMEType: navigationResponse.canShowMIMEType
        ) {
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        keep(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        keep(download)
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
        // Drop KVO stragglers for finished downloads: the observer is
        // invalidated in didFinish/didFail, but an already-dispatched Task
        // can land after finalize and must not resurrect the item.
        guard downloadManager?.downloads.contains(where: { $0.id == itemID && $0.isActive }) == true else { return }
        let received = progress.completedUnitCount
        let total = progress.totalUnitCount
        let now = Date()
        let last = downloadLastSample[itemID]
        // Throttle UI/DB churn to ~4Hz: KVO can fire per network chunk
        // (10s/sec). Speed math still samples at 0.15s but @Published
        // updates are gated below.
        let dtSinceSample = last.map { now.timeIntervalSince($0.date) } ?? .infinity
        let isComplete = total > 0 && received >= total
        if !isComplete, dtSinceSample < 0.25 {
            return
        }
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
        // If accounting says the bytes are all here, make sure the download
        // cannot spin at 100% forever (see scheduleDownloadFinalizeWatchdog).
        let effectiveTotal = total > 0 ? total : (downloadManager?.downloads.first(where: { $0.id == itemID })?.totalBytes ?? -1)
        if effectiveTotal > 0, received >= effectiveTotal, let download = activeDownloadObjects[itemID] {
            scheduleDownloadFinalizeWatchdog(itemID: itemID, download: download, totalBytes: effectiveTotal)
        }
    }

    /// Downloads WebKit never finishes: transfer accounting complete, file
    /// on disk, but `downloadDidFinish` lost (seen on some CDN video
    /// responses stuck at 100%). Finalize from our own accounting rather
    /// than spinning forever. Fires once per download; a no-op if the real
    /// callback already handled it.
    private func scheduleDownloadFinalizeWatchdog(itemID: UUID, download: WKDownload, totalBytes: Int64) {
        guard downloadWatchdogs.insert(itemID).inserted else { return }
        NSLog("[LeanDL] watchdog armed %@", itemID.uuidString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self else { return }
            self.downloadWatchdogs.remove(itemID)
            guard self.activeDownloadObjects[itemID] != nil,
                  let item = self.downloadManager?.downloads.first(where: { $0.id == itemID }),
                  item.state == .downloading else { return }
            let diskSize = (try? FileManager.default.attributesOfItem(atPath: item.destinationURL.path)[.size] as? Int64) ?? -1
            guard totalBytes > 0, diskSize >= totalBytes else { return }
            NSLog("Download %@ accounted complete but WebKit never finished it; finalizing", itemID.uuidString)
            self.finalizeDownload(download, itemID: itemID)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        forget(download)
        let key = ObjectIdentifier(download)
        let itemID = activeDownloadIDs[key]
        downloadProgressObservers[key]?.invalidate()
        downloadProgressObservers[key] = nil
        activeDownloadIDs[key] = nil
        guard let itemID else { return }
        finalizeDownload(download, itemID: itemID)
    }

    /// Shared by the real finish callback and the watchdog: mark the
    /// manager item complete with the on-disk byte count. Clears callback
    /// tracking first (idempotent with didFinish/didFail, which must clear
    /// it to resolve the item): the watchdog path never passed through
    /// them, and a lingering observer or key mapping would let later
    /// WebKit callbacks resolve or disturb the finalized item.
    private func finalizeDownload(_ download: WKDownload, itemID: UUID) {
        let key = ObjectIdentifier(download)
        downloadProgressObservers[key]?.invalidate()
        downloadProgressObservers[key] = nil
        activeDownloadIDs[key] = nil
        activeDownloadObjects[itemID] = nil
        downloadWatchdogs.remove(itemID)
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
        forget(download)
        let key = ObjectIdentifier(download)
        let itemID = activeDownloadIDs[key]
        downloadProgressObservers[key]?.invalidate()
        downloadProgressObservers[key] = nil
        activeDownloadIDs[key] = nil
        guard let itemID else { return }
        activeDownloadObjects[itemID] = nil
        downloadWatchdogs.remove(itemID)
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        downloadManager?.failDownload(id: itemID, errorDescription: error.localizedDescription, cancelled: cancelled)
        downloadLastSample[itemID] = nil
        // A failure nobody opens the panel for reads as "nothing happens".
        // Show it — but never for a cancellation the user asked for.
        if !cancelled {
            onDownloadFailed?()
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
