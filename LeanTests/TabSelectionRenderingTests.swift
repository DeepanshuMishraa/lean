import AppKit
import SwiftUI
import Testing
@testable import Lean

@Suite(.serialized)
struct TabSelectionRenderingTests {
    @Test("A stage attaches its requested page when it enters a window")
    @MainActor
    func stageAttachesPageWhenEnteringWindow() {
        let stage = LeanStageView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let page = NSView(frame: stage.bounds)
        stage.show(page)
        #expect(page.superview == nil)

        let window = NSWindow(
            contentRect: stage.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let content = NSView(frame: stage.bounds)
        window.contentView = content
        content.addSubview(stage)

        #expect(page.superview === stage)
    }

    @Test("Repeated tab switches show the selected web view on the first update")
    @MainActor
    func repeatedSwitchesShowSelectedWebView() throws {
        let (store, directory) = try makeIsolatedTestStore()
        store.isOnboardingPresented = false
        let first = store.newTab(url: URL(string: "about:blank"), select: true)
        let second = store.newTab(url: URL(string: "about:blank#second"), select: false)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let host = NSHostingView(rootView: LeanView(store: store, updater: AppUpdater()))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        defer {
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        try #require(first.webView.window === window)

        for index in 0..<200 {
            let selected = index.isMultiple(of: 2) ? second : first
            let previous = index.isMultiple(of: 2) ? first : second
            store.switchToTab(id: selected.id)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            #expect(selected.webView.window === window)
            #expect(previous.webView.window == nil)
        }
    }
}
