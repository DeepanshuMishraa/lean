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

    // MARK: - keys the page didn't use

    /// The last key handed to the page. WebKit sends a key the page didn't
    /// use back up the responder chain — the same event, a second time —
    /// where nothing takes it and macOS plays its "can't do that" sound.
    /// Editors that put the text in themselves leave WebKit thinking their
    /// keys unused, so typing into them beeped. Safari keeps those quiet,
    /// and so does this view. The app's own shortcuts never get this far:
    /// its key monitor takes them before the page sees the key.
    private var handed: NSEvent?

    override func keyDown(with event: NSEvent) {
        if let handed, LeanWebView.same(handed, event) {
            self.handed = nil
            return
        }
        handed = event
        super.keyDown(with: event)
    }

    /// The same key press: the event WebKit sends back is the one it was
    /// given, and no two presses share a timestamp.
    static func same(_ one: NSEvent, _ other: NSEvent) -> Bool {
        one === other || (one.timestamp == other.timestamp && one.keyCode == other.keyCode && one.type == other.type)
    }
}
