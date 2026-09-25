import WebKit

// The Web Inspector: WebKit's own, on the tab in front — from the View menu
// and its keys, as from Inspect Element in a page's right-click menu. The
// keys are Chrome's and Arc's: ⌥⌘I for the inspector, ⌥⌘J for the console,
// ⌥⌘C to pick an element on the page. Ported from Search (Inspector.swift).
//
// WebKit answers for its inspector only through names outside the public
// framework, so each is asked for before it is used; a WebKit without them
// leaves the menu doing nothing rather than the app falling over.

extension LeanStore {
    /// ⌥⌘I: the inspector, or put away if it is up.
    func toggleInspector() {
        guard let inspector = inspector() else { return }
        if asks(inspector, "isVisible") {
            send(inspector, "close")
        } else {
            send(inspector, "show")
        }
    }

    /// ⌥⌘J: the inspector, at its console.
    func showConsole() {
        guard let inspector = inspector() else { return }
        send(inspector, "showConsole")
    }

    /// ⌥⌘C: the inspector, and the next click on the page picks what it
    /// shows. Again, and the picking stops.
    func inspectElement() {
        guard let inspector = inspector() else { return }
        if !asks(inspector, "isVisible") { send(inspector, "show") }
        send(inspector, "toggleElementSelection")
    }

    /// The inspector of the tab in front — none without a page to look at.
    private func inspector() -> NSObject? {
        guard let tab = selectedTab, tab.hasWebView else { return nil }
        let web: WKWebView = tab.webView
        let get = NSSelectorFromString("_inspector")
        guard web.responds(to: get) else { return nil }
        return web.perform(get)?.takeUnretainedValue() as? NSObject
    }

    private func send(_ inspector: NSObject, _ name: String) {
        let selector = NSSelectorFromString(name)
        guard inspector.responds(to: selector) else { return }
        inspector.perform(selector)
    }

    private func asks(_ inspector: NSObject, _ name: String) -> Bool {
        let selector = NSSelectorFromString(name)
        guard inspector.responds(to: selector) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(inspector.method(for: selector), to: Getter.self)(inspector, selector)
    }
}

enum WebInspector {
    /// WebKit's "developer extras": Inspect Element in a page's right-click
    /// menu, and the Web Inspector the View menu opens (see above).
    /// isInspectable alone only lets Safari's Develop menu reach the page.
    /// The name is outside the public framework, so it is asked first.
    static func enableDeveloperExtras(_ preferences: WKPreferences) {
        let set = NSSelectorFromString("_setDeveloperExtrasEnabled:")
        guard preferences.responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(preferences.method(for: set), to: Setter.self)(preferences, set, true)
    }
}
