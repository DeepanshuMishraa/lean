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
    private var handed = OutstandingKeys(capacity: 16)

    override func keyDown(with event: NSEvent) {
        if handed.received(event) {
            return
        }
        super.keyDown(with: event)
    }

    /// The same key press: the event WebKit sends back is the one it was
    /// given, and no two presses share a timestamp.
    static func same(_ one: NSEvent, _ other: NSEvent) -> Bool {
        one === other || (one.timestamp == other.timestamp && one.keyCode == other.keyCode && one.type == other.type)
    }
}

/// Keys handed to the page and still awaiting WebKit's verdict. WebKit
/// sends a key the page didn't use back up the responder chain — the same
/// event, a second time. A single slot forgot earlier presses as soon as a
/// newer one arrived, so a late reply for the earlier press fell through
/// and was handled twice. Each press is retained until its own reply
/// returns; the capacity bound keeps a page that swallows keys (replies
/// that never come) from growing the list without limit.
struct OutstandingKeys {
    private var events: [NSEvent] = []
    private let capacity: Int

    init(capacity: Int = 16) {
        self.capacity = max(1, capacity)
    }

    /// True when `event` matches an outstanding press (consumed); false
    /// when it is new (retained for its reply).
    mutating func received(_ event: NSEvent) -> Bool {
        if let index = events.firstIndex(where: { LeanWebView.same($0, event) }) {
            events.remove(at: index)
            return true
        }
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        return false
    }
}
