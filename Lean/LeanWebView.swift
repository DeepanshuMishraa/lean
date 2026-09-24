import AppKit
import WebKit

/// WKWebView with a hook for extending the right-click menu.
///
/// WebKit builds its default menu first (link actions, Look Up, and
/// Inspect Element when `isInspectable`), then the hook appends Lean's
/// page actions. Overriding `willOpenMenu` is the macOS mechanism —
/// `contextMenuConfigurationForElement` is iOS-only.
final class LeanWebView: WKWebView {
    var contextMenuHook: ((NSMenu) -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        contextMenuHook?(menu)
    }
}
