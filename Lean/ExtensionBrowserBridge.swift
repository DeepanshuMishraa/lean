import AppKit
import WebKit

/// What extensions see of the browser: one window holding the store's tabs.
/// Without it extensions have no active tab, so popups like uBlock's report
/// "not a website" and toolbar actions have nothing to act on.
@available(macOS 15.4, *)
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    weak var store: LeanStore?

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        store?.tabs ?? []
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        store?.selectedTab
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .normal }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        NSApp.mainWindow?.frame ?? .zero
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        NSApp.mainWindow?.screen?.frame ?? .zero
    }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }
}

@available(macOS 15.4, *)
extension LeanTab: WKWebExtensionTab {
    private var extensionStore: LeanStore? { BrowserExtensionManager.shared.window.store }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        BrowserExtensionManager.shared.window
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        extensionStore?.tabs.firstIndex { $0.id == id } ?? 0
    }

    /// Never creates the view: asking about a sleeping tab must not wake it.
    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        hasWebView ? webView : nil
    }

    func title(for context: WKWebExtensionContext) -> String? { title }

    func url(for context: WKWebExtensionContext) -> URL? { url }

    func isPinned(for context: WKWebExtensionContext) -> Bool { isPinned }

    func isSelected(for context: WKWebExtensionContext) -> Bool { extensionStore?.selectedID == id }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !isLoading }

    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool { isPlayingMedia }

    func isMuted(for context: WKWebExtensionContext) -> Bool { isMuted }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        extensionStore?.switchToTab(id: id)
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        load(url)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        fromOrigin ? reloadFromOrigin() : reload()
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        goForward()
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        extensionStore?.close(self)
        completionHandler(nil)
    }
}
