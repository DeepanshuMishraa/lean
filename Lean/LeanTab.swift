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

    var onStateChange: (() -> Void)?
    var onOpenNewTab: ((URL) -> Void)?
    private var progressObserver: NSKeyValueObservation?

    init(
        dataStore: WKWebsiteDataStore,
        initialURL: URL?,
        isDark: Bool = false,
        scrollbarStyle: ScrollbarStyle = .normal,
        smoothScrolling: Bool = true,
        pageFont: LeanFont = .system
    ) {
        self.scrollbarStyle = scrollbarStyle
        self.smoothScrollingEnabled = smoothScrolling
        self.pageFont = pageFont
        let configuration = WKWebViewConfiguration()
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
            source: PageScripts.font(pageFont),
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
        if let host = initialURL?.host {
            self.title = host
            updateFavicon()
        }

        // Enable full opaque hardware acceleration and layer backing
        webView.wantsLayer = true
        webView.layer?.drawsAsynchronously = true
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = isDark ? NSColor.black : NSColor.white
        }

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

        Task { [weak self] in
            guard let self else { return }
            if let ruleList = await ContentBlocker.ruleList() {
                self.webView.configuration.userContentController.add(ruleList)
            }
            if let initialURL {
                self.load(initialURL)
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
            source: PageScripts.font(pageFont),
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

        Task { [weak self] in
            guard let self else { return }
            if let ruleList = await ContentBlocker.ruleList() {
                self.webView.configuration.userContentController.add(ruleList)
            }
        }
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

    func applyPageFont(_ font: LeanFont) {
        pageFont = font
        rebuildUserScripts()
        webView.evaluateJavaScript(PageScripts.font(font)) { _, _ in }
    }


    func displayTitle(isSelected: Bool, showFullTitle: Bool = true) -> String {
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
    func stop() {
        isLoading = false
        webView.stopLoading()
        onStateChange?()
    }

    func destroy() {
        progressObserver?.invalidate()
        progressObserver = nil
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
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
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
        // If WebKit natively displays this MIME type, always allow
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
            return
        }

        // Never trigger downloads for HTTP redirects or informational responses
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            if (300...399).contains(httpResponse.statusCode) {
                decisionHandler(.allow)
                return
            }

            // Only trigger download if header explicitly specifies "attachment"
            let disposition = (httpResponse.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
            if disposition.contains("attachment") {
                decisionHandler(.download)
                return
            }

            // If it is standard web content (HTML, text, json, xml, script, image), allow WebKit to render
            let mime = (httpResponse.mimeType ?? "").lowercased()
            if mime.isEmpty || mime.contains("html") || mime.contains("text") || mime.contains("json") || mime.contains("xml") || mime.contains("javascript") || mime.contains("svg") {
                decisionHandler(.allow)
                return
            }
        }

        // For main frame navigations without explicit attachment headers, allow rather than downloading
        if navigationResponse.isForMainFrame {
            decisionHandler(.allow)
            return
        }

        decisionHandler(.download)
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
        if let url = navigationAction.request.url {
            onOpenNewTab?(url)
        }
        return nil
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
