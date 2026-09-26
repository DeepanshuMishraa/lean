import Testing
import WebKit
@testable import Lean

/// Canary for the private WebKit inspector SPI Lean drives (shortcuts,
/// View menu, Inspect Element). If Apple renames/removes these, every
/// inspector entry point silently no-ops by design — this fails loudly
/// instead.
struct InspectorSpiTests {
    @MainActor
    @Test("Inspector SPI present")
    func spiPresent() {
        #expect(WKPreferences().responds(to: NSSelectorFromString("_setDeveloperExtrasEnabled:")))
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        #expect(webView.responds(to: NSSelectorFromString("_inspector")))
        guard let inspector = webView.perform(NSSelectorFromString("_inspector"))?
            .takeUnretainedValue() as? NSObject
        else {
            Issue.record("no _WKInspector object")
            return
        }
        for name in ["isVisible", "show", "close", "showConsole", "toggleElementSelection"] {
            #expect(inspector.responds(to: NSSelectorFromString(name)), "missing \(name)")
        }
    }
}
