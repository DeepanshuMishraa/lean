import Foundation
import Testing
import WebKit
@testable import Lean

private final class DummyMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {}
}

struct LeanTabPopupTests {
    @MainActor
    @Test("Popup configuration carrying opener handlers does not crash init")
    func popupConfigurationInit() {
        // Reproduces what WebKit hands `createWebViewWith` for window.open
        // popups (e.g. Figma's Continue with Google): a configuration whose
        // user content controller already carries the opener's scripts and
        // the `pageReady` message handler. Re-adding that handler name used
        // to throw a duplicate-name NSException and crash the app.
        let popupConfiguration = WKWebViewConfiguration()
        popupConfiguration.userContentController.addUserScript(
            WKUserScript(
                source: "void 0;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        popupConfiguration.userContentController.add(
            DummyMessageHandler(),
            name: PageScripts.pageReadyMessageName
        )

        let tab = LeanTab(
            dataStore: .default(),
            initialURL: nil,
            configuration: popupConfiguration
        )
        #expect(tab.url == nil)
        #expect(tab.title == "New Tab")
    }
}
