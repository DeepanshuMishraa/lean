import AppKit
import SwiftUI

/// Container for a windowed CEF browser. Owned by the LeanTab (same lifetime
/// pattern as the WKWebView); the representable below returns the stored
/// instance so tab switches re-insert the same view instead of orphaning
/// the renderer.
final class CEFContainerView: NSView {
    weak var tab: LeanTab?

    override func layout() {
        super.layout()
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
