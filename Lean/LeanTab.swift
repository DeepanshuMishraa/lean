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
    /// Engine this tab was created with. Never hot-swapped: changing the
    /// global engine choice only affects newly opened tabs.
    private(set) var engineKind: BrowserEngineKind

    // MARK: - CEF engine state (nil for WebKit tabs)
    var cefHost: CEFBrowserHost?
    private var cefContainer: CEFContainerView?
    private var pendingCEFURL: URL?
    private var cefAttached = false
    private var cefDownloadItems: [String: UUID] = [:]
    private var cefDownloadSamples: [UUID: (bytes: Int64, date: Date, speed: Double)] = [:]

    var isSettingsPage: Bool {
        guard let url = url else { return false }
        return url.absoluteString == "lean://settings" || (url.scheme == "lean" && url.host == "settings")
    }

    var onStateChange: (() -> Void)?
    var onOpenNewTab: ((URL, WKWebViewConfiguration) -> WKWebView?)?
    var onCloseTab: (() -> Void)?
    /// CEF popup URLs (v1: opened as plain new tabs inheriting the store engine).
    var onOpenNewTabURL: ((URL) -> Void)?
    var downloadManager: DownloadManager?
    var mediaPermissionStore: MediaPermissionStore?
    private var progressObserver: NSKeyValueObservation?
    private var navigationObservers: [NSKeyValueObservation] = []
    private var activeDownloadIDs: [ObjectIdentifier: UUID] = [:]
    private var downloadProgressObservers: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var downloadLastSample: [UUID: (bytes: Int64, date: Date, speed: Double)] = [:]
    private var activeDownloadObjects: [UUID: WKDownload] = [:]

    func cancelActiveDownload(id: UUID) {
        activeDownloadObjects[id]?.cancel()
        activeDownloadObjects[id] = nil
        if let cefKey = cefDownloadItems.first(where: { $0.value == id })?.key {
            cefDownloadItems.removeValue(forKey: cefKey)
            cefDownloadSamples.removeValue(forKey: id)
            cefHost?.cancelDownload(cefKey)
        }
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
        engineKind: BrowserEngineKind = .webKit,
        configuration: WKWebViewConfiguration? = nil
    ) {
        self.engineKind = engineKind
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

        if engineKind == .cef, CEFIntegration.isAvailable() {
            setupCEFHost()
        }

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
        if let cef = cefHost {
            pendingCEFURL = url
            isLoading = true
            onStateChange?()
            updateFavicon(for: url)
            if cefAttached {
                cef.loadURL(url.absoluteString)
            }
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
        if let cef = cefHost {
            isLoading = true
            onStateChange?()
            cef.goBack()
            return
        }
        isLoading = true
        onStateChange?()
        webView.goBack()
    }
    func goForward() {
        if let cef = cefHost {
            isLoading = true
            onStateChange?()
            cef.goForward()
            return
        }
        isLoading = true
        onStateChange?()
        webView.goForward()
    }
    func reload() {
        if let cef = cefHost {
            isLoading = true
            onStateChange?()
            cef.reload()
            return
        }
        isLoading = true
        onStateChange?()
        webView.reload()
    }
    func reloadFromOrigin() {
        if let cef = cefHost {
            isLoading = true
            onStateChange?()
            cef.reloadFromOrigin()
            return
        }
        isLoading = true
        onStateChange?()
        webView.reloadFromOrigin()
    }
    func stop() {
        if let cef = cefHost {
            isLoading = false
            cef.stopLoading()
            onStateChange?()
            return
        }
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
        onCloseTab = nil
        onOpenNewTabURL = nil

        if let cef = cefHost {
            cef.close()
            cefHost = nil
        }
        cefContainer?.removeFromSuperview()
        cefContainer = nil
        pendingCEFURL = nil
        cefDownloadItems.removeAll()
        cefDownloadSamples.removeAll()

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

    func zoomIn() {
        if let cef = cefHost { cef.zoomIn(); return }
        webView.pageZoom = min(webView.pageZoom + 0.1, 3)
    }
    func zoomOut() {
        if let cef = cefHost { cef.zoomOut(); return }
        webView.pageZoom = max(webView.pageZoom - 0.1, 0.5)
    }
    func resetZoom() {
        if let cef = cefHost { cef.resetZoom(); return }
        webView.pageZoom = 1
    }

    func find(_ query: String) {
        guard !query.isEmpty else { return }
        if let cef = cefHost { cef.find(query); return }
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
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
           ExternalLinkPolicy.shouldOpenExternally(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
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
        // Client certificates and other methods have no in-app UI: fail fast
        // instead of hanging the page silently.
        completionHandler(.cancelAuthenticationChallenge, nil)
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
        guard let url = navigationAction.request.url else { return nil }
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
        presentAlert(message: message, showsTextField: false, isConfirmation: false) { confirmed, _ in
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
        let originKey: String = {
            if origin.port != 0 {
                return "\(origin.protocol)://\(origin.host):\(origin.port)"
            }
            return "\(origin.protocol)://\(origin.host)"
        }()
        if let stored = mediaPermissionStore?.decision(forOriginKey: originKey) {
            decisionHandler(stored ? .grant : .deny)
            return
        }
        guard let window = webView.window else {
            decisionHandler(.deny)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Allow camera and microphone?"
        alert.informativeText = "\(origin.host) wants to use your camera and microphone."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        alert.alertStyle = .informational
        alert.beginSheetModal(for: window) { [weak self] response in
            let allowed = response == .alertFirstButtonReturn
            self?.mediaPermissionStore?.setDecision(allowed, forOriginKey: originKey)
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
        guard let window = webView.window else {
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

// MARK: - CEF engine

extension LeanTab {
    private func setupCEFHost() {
        guard CEFBootstrap.ensureInitialized() else { return }
        let host = CEFBrowserHost()
        cefHost = host

        host.onTitle = { [weak self] title in
            guard let self else { return }
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.title = clean.isEmpty ? (self.url?.host ?? "New Tab") : clean
            self.onStateChange?()
        }
        host.onURL = { [weak self] urlString in
            guard let self else { return }
            if let url = URL(string: urlString) {
                self.url = url
            }
            self.onStateChange?()
        }
        host.onLoadingState = { [weak self] loading, back, forward in
            guard let self else { return }
            self.isLoading = loading
            self.canGoBack = back
            self.canGoForward = forward
            self.onStateChange?()
        }
        host.onFaviconURLs = { [weak self] urls in
            guard let self else { return }
            self.updateFavicon(for: self.url, explicitIconURL: urls.first)
        }
        host.onLoadError = { [weak self] _, _ in
            guard let self else { return }
            self.isLoading = false
            self.onStateChange?()
        }
        host.onClose = { [weak self] in
            self?.onCloseTab?()
        }
        host.onPopupURL = { [weak self] urlString in
            guard let self, let url = URL(string: urlString) else { return }
            self.onOpenNewTabURL?(url)
        }
        host.onJSAlert = { [weak self] message, id in
            guard let self else { return }
            self.presentAlert(message: message, showsTextField: false, isConfirmation: false) { _, _ in
                self.cefHost?.completeJSDialog(id, ok: true, text: nil)
            }
        }
        host.onJSConfirm = { [weak self] message, id in
            guard let self else { return }
            self.presentAlert(message: message, showsTextField: false, isConfirmation: true) { confirmed, _ in
                self.cefHost?.completeJSDialog(id, ok: confirmed, text: nil)
            }
        }
        host.onJSPrompt = { [weak self] message, defaultText, id in
            guard let self else { return }
            self.presentAlert(message: message, showsTextField: true, isConfirmation: true, defaultText: defaultText) { confirmed, text in
                self.cefHost?.completeJSDialog(id, ok: confirmed, text: text)
            }
        }
        host.onAuthChallenge = { [weak self] challengeHost, realm, id in
            self?.presentCEFCredentialsSheet(host: challengeHost, realm: realm, id: id)
        }
        host.onMediaPermission = { [weak self] originURLString, id in
            self?.handleCEFMediaPermission(originURLString: originURLString, id: id)
        }
        host.onDownloadStarted = { [weak self] downloadId, suggestedName, sourceURLString, total in
            self?.startCEFDownload(id: downloadId, suggestedName: suggestedName,
                                   sourceURLString: sourceURLString, totalBytes: total)
        }
        host.onDownloadProgress = { [weak self] downloadId, received, total in
            self?.updateCEFDownload(id: downloadId, receivedBytes: received, totalBytes: total)
        }
        host.onDownloadFinished = { [weak self] downloadId, _ in
            self?.finishCEFDownload(id: downloadId)
        }
        host.onDownloadFailed = { [weak self] downloadId, cancelled in
            self?.failCEFDownload(id: downloadId, cancelled: cancelled)
        }
    }

    /// The single container view for this tab's CEF browser. Returned to the
    /// SwiftUI representable so tab switches re-insert the same view.
    func cefContainerView() -> CEFContainerView {
        if let cefContainer { return cefContainer }
        let view = CEFContainerView()
        view.tab = self
        cefContainer = view
        return view
    }

    /// Creates the browser inside `view` (first presentation only).
    func attachCEF(to view: NSView) {
        guard let host = cefHost, !cefAttached else { return }
        cefAttached = true
        // Only flush a pending URL that still matches the tab; a stale one
        // (e.g. from before a settings navigation) must not resurrect.
        let initial: URL?
        if let pending = pendingCEFURL, pending == url {
            initial = pending
        } else {
            initial = url
        }
        pendingCEFURL = initial
        host.create(in: view, initialURL: initial?.absoluteString)
    }

    private func presentCEFCredentialsSheet(host challengeHost: String, realm: String, id: Int64) {
        guard let window = webView.window else {
            cefHost?.completeAuth(id, username: nil, password: nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Sign in to \(challengeHost)"
        alert.informativeText = realm.isEmpty
            ? "This site is asking for a username and password."
            : realm
        alert.alertStyle = .informational
        let username = NSTextField(string: "")
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
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else {
                self?.cefHost?.completeAuth(id, username: nil, password: nil)
                return
            }
            self?.cefHost?.completeAuth(id, username: username.stringValue, password: password.stringValue)
        }
    }

    private func handleCEFMediaPermission(originURLString: String, id: Int64) {
        guard let originURL = URL(string: originURLString),
              let originKey = MediaPermissionStore.originKey(for: originURL) else {
            cefHost?.completeMediaPermission(id, allow: false)
            return
        }
        if let stored = mediaPermissionStore?.decision(forOriginKey: originKey) {
            cefHost?.completeMediaPermission(id, allow: stored)
            return
        }
        guard let window = webView.window else {
            cefHost?.completeMediaPermission(id, allow: false)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Allow camera and microphone?"
        alert.informativeText = "\(originURL.host ?? originKey) wants to use your camera and microphone."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        alert.alertStyle = .informational
        alert.beginSheetModal(for: window) { [weak self] response in
            let allowed = response == .alertFirstButtonReturn
            self?.mediaPermissionStore?.setDecision(allowed, forOriginKey: originKey)
            self?.cefHost?.completeMediaPermission(id, allow: allowed)
        }
    }

    private func startCEFDownload(id: String, suggestedName: String,
                                  sourceURLString: String, totalBytes: Int64) {
        let manager = downloadManager
        let fallbackDir = DownloadManager.defaultDownloadsDirectory()
        try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        let fileName = suggestedName.isEmpty ? "download" : suggestedName
        let destination = manager?.uniqueDestination(for: fileName)
            ?? fallbackDir.appendingPathComponent(fileName)
        let total = totalBytes > 0 ? totalBytes : Int64(-1)
        let itemID = manager?.beginDownload(
            fileName: destination.lastPathComponent,
            sourceURL: URL(string: sourceURLString),
            destinationURL: destination,
            totalBytes: total
        ) ?? UUID()
        cefDownloadItems[id] = itemID
        cefDownloadSamples[itemID] = (bytes: 0, date: Date(), speed: 0)
        cefHost?.continueDownload(id, path: destination.path)
    }

    private func updateCEFDownload(id: String, receivedBytes: Int64, totalBytes: Int64) {
        guard let itemID = cefDownloadItems[id] else { return }
        let now = Date()
        var speed = cefDownloadSamples[itemID]?.speed ?? 0
        if let last = cefDownloadSamples[itemID] {
            let dt = now.timeIntervalSince(last.date)
            if dt > 0.15 {
                let instant = Double(receivedBytes - last.bytes) / dt
                if instant >= 0 {
                    speed = last.speed * 0.6 + instant * 0.4
                }
                cefDownloadSamples[itemID] = (bytes: receivedBytes, date: now, speed: speed)
            }
        }
        downloadManager?.updateProgress(
            id: itemID,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes > 0 ? totalBytes : Int64(-1),
            speedBytesPerSec: speed
        )
    }

    private func finishCEFDownload(id: String) {
        guard let itemID = cefDownloadItems[id] else { return }
        cefDownloadItems[id] = nil
        // A cancelled download can still report finish if the cancel raced
        // the final bytes: drop the partial file instead of presenting it.
        if downloadManager?.downloads.first(where: { $0.id == itemID })?.state == .cancelled {
            if let dst = downloadManager?.downloads.first(where: { $0.id == itemID })?.destinationURL {
                try? FileManager.default.removeItem(at: dst)
            }
            downloadManager?.failDownload(id: itemID, errorDescription: "Cancelled", cancelled: true)
            cefDownloadSamples[itemID] = nil
            return
        }
        if let item = downloadManager?.downloads.first(where: { $0.id == itemID }) {
            let diskSize = (try? FileManager.default.attributesOfItem(atPath: item.destinationURL.path)[.size] as? Int64) ?? nil
            let received = diskSize ?? -1
            let total = received >= 0 ? received : Int64(-1)
            downloadManager?.updateProgress(id: itemID, receivedBytes: received >= 0 ? received : 0,
                                            totalBytes: total, speedBytesPerSec: 0)
        }
        let fileName = downloadManager?.downloads.first(where: { $0.id == itemID })?.destinationURL.lastPathComponent
        downloadManager?.finishDownload(id: itemID, fileName: fileName)
        cefDownloadSamples[itemID] = nil
    }

    private func failCEFDownload(id: String, cancelled: Bool) {
        guard let itemID = cefDownloadItems[id] else { return }
        cefDownloadItems[id] = nil
        cefDownloadSamples[itemID] = nil
        downloadManager?.failDownload(id: itemID,
                                      errorDescription: cancelled ? "Cancelled" : "Download failed",
                                      cancelled: cancelled)
    }
}
