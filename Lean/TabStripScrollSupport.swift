import AppKit
import SwiftUI

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
