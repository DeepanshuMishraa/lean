import AppKit
import WebKit

@MainActor
final class LeanTab: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView

    @Published private(set) var title = "New Tab"
    @Published private(set) var url: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published var snapshot: NSImage? = nil
    @Published var favicon: NSImage? = nil
    private(set) var scrollbarStyle: ScrollbarStyle
    private(set) var smoothScrollingEnabled: Bool
    private(set) var pageFont: LeanFont
    private(set) var pageHeadingWeight: Int
    private(set) var pageBodyWeight: Int
    private(set) var adBlockingEnabled: Bool

    var isSettingsPage: Bool {
        guard let url = url else { return false }
        return url.absoluteString == "lean://settings" || (url.scheme == "lean" && url.host == "settings")
    }

    var onStateChange: (() -> Void)?
    var onOpenNewTab: ((URL, WKWebViewConfiguration) -> WKWebView?)?
    private var progressObserver: NSKeyValueObservation?
    private var navigationObservers: [NSKeyValueObservation] = []

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
        configuration: WKWebViewConfiguration? = nil
    ) {
        self.scrollbarStyle = scrollbarStyle
        self.smoothScrollingEnabled = smoothScrolling
        self.pageFont = pageFont
        self.pageHeadingWeight = pageHeadingWeight
        self.pageBodyWeight = pageBodyWeight
        self.adBlockingEnabled = adBlockingEnabled
        let configuration = configuration ?? WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
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
            source: PageScripts.smoothScrolling(enabled: smoothScrolling),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(smoothScript)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: PageScripts.pageReady,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.configuration.userContentController.add(self, name: PageScripts.pageReadyMessageName)
        self.url = initialURL
        if initialURL?.scheme == "lean" && (initialURL?.host == "settings" || initialURL?.absoluteString == "lean://settings") {
            self.title = "Settings"
        } else if let host = initialURL?.host {
            self.title = host
            updateFavicon()
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

        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif

        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            if webView.estimatedProgress >= 0.7 {
                DispatchQueue.main.async {
                    guard let self, self.isLoading else { return }
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

        applyAdBlocking(adBlockingEnabled)

        if let initialURL {
            self.load(initialURL)
        }
    }

    func applyAdBlocking(_ enabled: Bool) {
        adBlockingEnabled = enabled
        Task { [weak self] in
            let ruleLists = await ContentBlocker.ruleLists()
            guard let self, self.adBlockingEnabled == enabled else { return }
            if enabled {
                for ruleList in ruleLists {
                    // Remove-then-add keeps this idempotent: rebuildUserScripts()
                    // preserves rule lists, so re-enabling must not stack duplicates.
                    self.webView.configuration.userContentController.remove(ruleList)
                    self.webView.configuration.userContentController.add(ruleList)
                }
            } else {
                for ruleList in ruleLists {
                    self.webView.configuration.userContentController.remove(ruleList)
                }
            }
        }
    }

    func applyTheme(isDark: Bool) {
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = isDark ? NSColor.black : NSColor.white
        }
    }

    private func rebuildUserScripts() {
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
        webView.configuration.userContentController.addUserScript(
            WKUserScript(
                source: PageScripts.pageReady,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        applyAdBlocking(adBlockingEnabled)
    }

    func applyScrollbarStyle(_ style: ScrollbarStyle) {
        self.scrollbarStyle = style
        rebuildUserScripts()
        let script = PageScripts.scrollbar(style)
        webView.evaluateJavaScript(script) { _, _ in }
    }

    func applySmoothScrolling(_ enabled: Bool) {
        self.smoothScrollingEnabled = enabled
        rebuildUserScripts()
        let script = PageScripts.smoothScrolling(enabled: enabled)
        webView.evaluateJavaScript(script) { _, _ in }
    }

    func applyPageFont(_ font: LeanFont, headingWeight: Int = 0, bodyWeight: Int = 0) {
        pageFont = font
        pageHeadingWeight = headingWeight
        pageBodyWeight = bodyWeight
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
        isLoading = true
        onStateChange?()
        updateFavicon(for: url)
        webView.load(URLRequest(url: url))
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
        isLoading = true
        onStateChange?()
        webView.reload()
    }
    func reloadFromOrigin() {
        isLoading = true
        onStateChange?()
        webView.reloadFromOrigin()
    }
    func stop() {
        isLoading = false
        webView.stopLoading()
        onStateChange?()
    }

    func destroy() {
        progressObserver?.invalidate()
        progressObserver = nil
        navigationObservers.forEach { $0.invalidate() }
        navigationObservers.removeAll()
        isLoading = false
        onStateChange = nil
        onOpenNewTab = nil

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
        webView.configuration.userContentController.removeAllUserScripts()
        webView.removeFromSuperview()
    }

    func zoomIn() { webView.pageZoom = min(webView.pageZoom + 0.1, 3) }
    func zoomOut() { webView.pageZoom = max(webView.pageZoom - 0.1, 0.5) }
    func resetZoom() { webView.pageZoom = 1 }

    func find(_ query: String) {
        guard !query.isEmpty else { return }
        webView.find(query, configuration: WKFindConfiguration()) { _ in }
    }

    func captureSnapshot() {
        guard webView.bounds.width > 0 && webView.bounds.height > 0 else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 440 // High DPI thumbnail width
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
        url = webView.url
        onStateChange?()
    }
}

extension LeanTab: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == PageScripts.pageReadyMessageName,
              message.frameInfo.isMainFrame,
              message.webView === webView else {
            return
        }
        isLoading = false
        refreshState()
    }
}

extension LeanTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
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
        isLoading = false
        refreshState()
        applyScrollbarStyle(scrollbarStyle)

        // Extract favicon link tag from DOM if available
        let js = "document.querySelector('link[rel*=\"icon\"]') ? document.querySelector('link[rel*=\"icon\"]').href : ''"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            let explicitHref = (result as? String)?.nilIfEmpty
            self?.updateFavicon(for: webView.url, explicitIconURL: explicitHref)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.captureSnapshot()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        isLoading = false
        refreshState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        isLoading = false
        refreshState()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        // Only trigger download if Content-Disposition explicitly specifies attachment
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            let disposition = (httpResponse.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
            if disposition.contains("attachment") {
                decisionHandler(.download)
                return
            }
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
        guard let url = navigationAction.request.url else { return nil }
        return onOpenNewTab?(url, configuration)
    }
}

extension LeanTab: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            completionHandler(nil)
            return
        }

        var destination = downloadsURL.appendingPathComponent(suggestedFilename)
        var counter = 1
        let name = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension

        while FileManager.default.fileExists(atPath: destination.path) {
            let uniqueName = ext.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(ext)"
            destination = downloadsURL.appendingPathComponent(uniqueName)
            counter += 1
        }

        completionHandler(destination)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
