import AppKit
import SwiftUI

/// Container for a windowed CEF browser. CEF reparents its native host view
/// into the window's content view on macOS, so keep a separate anchor and
/// position it over this SwiftUI-owned placeholder.
final class CEFContainerView: NSView {
    weak var tab: LeanTab?
    private let browserParent = NSView()
    private var isBrowserCreated = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(browserParent)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        browserParent.isHidden = window == nil
        attachBrowserIfReady()
        positionBrowser()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        attachBrowserIfReady()
        positionBrowser()
    }

    func browserCreated() {
        isBrowserCreated = true
        positionBrowser()
    }

    private func attachBrowserIfReady() {
        guard bounds.width > 0, bounds.height > 0,
              let rootView = window?.contentView
        else { return }
        if browserParent.superview !== rootView {
            rootView.addSubview(browserParent)
        }
        browserParent.frame = convert(bounds, to: rootView)
        tab?.attachCEF(to: browserParent)
    }

    private func positionBrowser() {
        guard isBrowserCreated,
              let rootView = window?.contentView
        else { return }
        if browserParent.superview !== rootView {
            rootView.addSubview(browserParent)
        }
        browserParent.frame = convert(bounds, to: rootView)
        browserParent.isHidden = isHidden
        tab?.cefHost?.notifyParentResized()
    }
}

struct CEFEngineView: NSViewRepresentable {
    @ObservedObject var tab: LeanTab

    func makeNSView(context: Context) -> NSView {
        tab.cefContainerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
