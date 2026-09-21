import AppKit
import SwiftUI

/// Hosts a windowed CEF browser inline in the SwiftUI hierarchy (same
/// lifetime pattern as the WKWebView): the representable returns the
/// tab-owned container, so tab switches re-insert the same view instead of
/// orphaning the renderer.
///
/// Do NOT float CEF content above the window in `window.contentView` as an
/// overlay: it paints over the SwiftUI hosting view, hiding popovers and
/// the command palette, ignoring the card's rounded corners, and desyncing
/// from Zen show/hide geometry. Inline hosting keeps z-order, clipping,
/// and layout identical to WebKit tabs.
final class CEFContainerView: NSView {
    weak var tab: LeanTab?

    override func layout() {
        super.layout()
        tab?.cefHost?.notifyParentResized()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        tab?.cefHost?.notifyParentResized()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tab?.cefHost?.notifyParentResized()
    }
}

struct CEFEngineView: NSViewRepresentable {
    @ObservedObject var tab: LeanTab

    func makeNSView(context: Context) -> NSView {
        let view = tab.cefContainerView()
        tab.attachCEF(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
