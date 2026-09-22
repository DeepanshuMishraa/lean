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
    var acceptsInput = true

    override func hitTest(_ point: NSPoint) -> NSView? {
        acceptsInput ? super.hitTest(point) : nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        tab?.cefHost?.notifyParentResized()
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        CEFManager.beginLiveResizeMessagePump()
    }

    override func viewDidEndLiveResize() {
        CEFManager.endLiveResizeMessagePump()
        super.viewDidEndLiveResize()
    }
}

struct CEFEngineView: NSViewRepresentable {
    @ObservedObject var tab: LeanTab
    let acceptsInput: Bool

    func makeNSView(context: Context) -> CEFContainerView {
        let view = tab.cefContainerView()
        view.acceptsInput = acceptsInput
        tab.attachCEF(to: view)
        return view
    }

    func updateNSView(_ nsView: CEFContainerView, context: Context) {
        nsView.acceptsInput = acceptsInput
    }
}
