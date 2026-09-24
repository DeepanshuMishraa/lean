import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TabContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TabViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct HorizontalScrollMetrics: Equatable {
    var offset: CGFloat = 0
}

struct HorizontalScrollWheelBridge: NSViewRepresentable {
    @Binding var metrics: HorizontalScrollMetrics

    func makeNSView(context: Context) -> HorizontalScrollWheelView {
        let view = HorizontalScrollWheelView()
        let metricsBinding = _metrics
        view.onMetricsChange = { metricsBinding.wrappedValue = $0 }
        return view
    }

    func updateNSView(_ nsView: HorizontalScrollWheelView, context: Context) {
        let metricsBinding = _metrics
        nsView.onMetricsChange = { metricsBinding.wrappedValue = $0 }
        DispatchQueue.main.async {
            nsView.reportCurrentMetrics()
        }
    }
}

final class HorizontalScrollWheelView: NSView {
    var onMetricsChange: ((HorizontalScrollMetrics) -> Void)?
    private var monitor: Any?
    private var lastMetrics = HorizontalScrollMetrics()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollWheel(event) ?? event
        }
        reportCurrentMetrics()
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func reportCurrentMetrics() {
        guard let window,
              let scrollView = horizontalScrollView(in: window.contentView, at: window.mouseLocationOutsideOfEventStream) else {
            return
        }
        reportMetrics(for: scrollView)
    }

    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard let window,
              event.window === window,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              let scrollView = horizontalScrollView(in: window.contentView, at: event.locationInWindow),
              let documentView = scrollView.documentView else {
            return event
        }

        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else {
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.reportMetrics(for: scrollView)
            }
            return event
        }

        let maxX = max(0, documentView.frame.width - scrollView.contentView.bounds.width)
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 24
        let nextX = min(max(scrollView.contentView.bounds.origin.x - event.scrollingDeltaY * multiplier, 0), maxX)
        guard nextX != scrollView.contentView.bounds.origin.x else { return event }

        scrollView.contentView.scroll(to: NSPoint(x: nextX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        reportMetrics(for: scrollView)
        return nil
    }

    private func reportMetrics(for scrollView: NSScrollView) {
        let metrics = HorizontalScrollMetrics(
            offset: scrollView.contentView.bounds.origin.x
        )
        guard metrics != lastMetrics else { return }
        lastMetrics = metrics
        onMetricsChange?(metrics)
    }

    private func horizontalScrollView(in view: NSView?, at point: NSPoint) -> NSScrollView? {
        guard let view else { return nil }
        if let scrollView = view as? NSScrollView,
           scrollView.documentView?.frame.width ?? 0 > scrollView.contentView.bounds.width,
           scrollView.bounds.contains(scrollView.convert(point, from: nil)) {
            return scrollView
        }
        for subview in view.subviews {
            if let match = horizontalScrollView(in: subview, at: point) {
                return match
            }
        }
        return nil
    }
}

// MARK: - Window-drag veto for tab items
//
// The window uses a hidden title bar with full-size content, so a press-and-
// move that starts on a tab is claimed as a window drag (titlebar region and
// draggable SwiftUI backgrounds) and the whole window moves instead of the
// tab. This transparent front overlay claims left-mouse presses so AppKit
// asks IT — and it always answers NO — whether the window may move. The
// press is then forwarded to the topmost SwiftUI view visually under it, so
// clicks, text selection, close buttons and native drag-reorder behave
// exactly as without it. Right/middle clicks and scrolling never touch it
// and pass through as usual.
struct WindowDragVeto: NSViewRepresentable {
    func makeNSView(context: Context) -> VetoView { VetoView() }

    func updateNSView(_ nsView: VetoView, context: Context) {}

    final class VetoView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

        private var forwardingEvent = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !forwardingEvent,
                  NSApp.currentEvent?.type == .leftMouseDown,
                  bounds.contains(point) else { return nil }
            return self
        }

        private func forward(_ event: NSEvent) {
            forwardingEvent = true
            NSApp.sendEvent(event)
            forwardingEvent = false
        }

        override func mouseDown(with event: NSEvent) { forward(event) }
        override func mouseDragged(with event: NSEvent) { forward(event) }
        override func mouseUp(with event: NSEvent) { forward(event) }
    }
}

// MARK: - Tab reorder (native drag & drop)
//
// The strips used to reorder with a SwiftUI DragGesture. That gesture only
// claims the pointer after ~8pt of movement, while the window (hidden title
// bar, full-size content view) treats a press-and-move on a tab background as
// a window drag — so the whole window moved instead of the tab. A native
// dragging session captures the pointer for the tab instead, and hovering a
// neighbour live-moves the dragged tab there, Safari-style.
//
// Used by both the horizontal top strip and the vertical sidebar strip.
final class TabReorderDropDelegate: DropDelegate {
    private let targetID: LeanTab.ID
    private let store: LeanStore
    private let onHighlight: (Bool) -> Void

    init(targetID: LeanTab.ID, store: LeanStore, onHighlight: @escaping (Bool) -> Void) {
        self.targetID = targetID
        self.store = store
        self.onHighlight = onHighlight
    }

    private var draggedID: LeanTab.ID? {
        guard let id = store.draggingTabID, id != targetID,
              store.tabs.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func validateDrop(info: DropInfo) -> Bool { draggedID != nil }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedID,
              let target = store.tabs.firstIndex(where: { $0.id == targetID }) else { return }
        onHighlight(true)
        store.moveTab(id: dragged, toIndex: target)
    }

    func dropExited(info: DropInfo) { onHighlight(false) }

    func performDrop(info: DropInfo) -> Bool {
        onHighlight(false)
        store.draggingTabID = nil
        store.saveSession()
        return true
    }
}
