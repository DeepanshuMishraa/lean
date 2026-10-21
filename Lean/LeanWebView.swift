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

    /// Parked in an invisible window while the system picture-in-picture window plays its video. The
    /// stage must not take the page back: out of every window, that window closes and the video pauses.
    var isParkedForPictureInPicture = false

    /// Where the last right-click landed, in page (CSS) coordinates, so an
    /// action chosen from the menu can ask the page what was under the cursor.
    private(set) var lastContextPoint: CGPoint = .zero

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        lastContextPoint = pagePoint(of: event)
        contextMenuHook?(menu)
    }

    private func pagePoint(of event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        let top = isFlipped ? local.y : bounds.height - local.y
        return CGPoint(x: local.x / pageZoom, y: top / pageZoom)
    }

    // MARK: - force click

    /// A force click deepened to its second stage, at this point in page
    /// (CSS) coordinates. Once per press.
    var onForceClick: ((CGPoint) -> Void)?

    /// Where the last press landed, from the window's top-left corner: a
    /// link peek grows out of this point.
    private(set) var lastPressInWindow: CGPoint?

    /// From a force click until just after its release. The click that ends
    /// a force click is still a click, and must not follow the link it peeked at.
    private(set) var isForceClicking = false
    private var forceClickRelease: DispatchWorkItem?

    override func mouseDown(with event: NSEvent) {
        if let height = window?.contentView?.bounds.height {
            lastPressInWindow = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
        }
        forceClickRelease?.cancel()
        isForceClicking = false
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard isForceClicking else { return }
        // WebKit decides the click's navigation after mouseUp returns.
        let release = DispatchWorkItem { [weak self] in self?.isForceClicking = false }
        forceClickRelease = release
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: release)
    }

    override func pressureChange(with event: NSEvent) {
        super.pressureChange(with: event)
        guard event.stage >= 2, !isForceClicking else { return }
        isForceClicking = true
        onForceClick?(pagePoint(of: event))
    }

    /// Keep horizontal rubber-banding for swipe navigation, but do not bounce
    /// past the page's top or bottom.
    /// Doing this natively avoids the WebKit wheel-listener bug caused by
    /// `overscroll-behavior-y: none`.
    func configureScrolling() {
        let set = NSSelectorFromString("_setRubberBandingEnabled:")
        guard responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
        let left: UInt = 1 << 0
        let right: UInt = 1 << 2
        unsafeBitCast(method(for: set), to: Setter.self)(self, set, left | right)
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
