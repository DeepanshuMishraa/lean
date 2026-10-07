import SwiftUI

@main
struct LeanApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = LeanStore()
    @StateObject private var updater = AppUpdater()

    init() {
        Self.registerCustomFonts()
    }

    private static func registerCustomFonts() {
        let fontNames = ["Geist-Variable", "GeistMono-Variable"]
        for name in fontNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        let devPaths = [
            "Lean/Resources/Fonts/Geist-Variable.ttf",
            "Lean/Resources/Fonts/GeistMono-Variable.ttf"
        ]
        for path in devPaths {
            if FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            LeanView(store: store, updater: updater)
                .frame(minWidth: 720, minHeight: 480)
                .ignoresSafeArea(.all)
                // Links from elsewhere: a click in Mail, Slack, a PDF —
                // macOS hands the address to whichever app owns http, which
                // is this one once it is the default browser (see
                // DefaultBrowser + Info.plist CFBundleURLTypes).
                // Local pages too: Finder's Open With, or a double-click on
                // an .html file once Lean is its default app, hands us a
                // file URL.
                .onOpenURL { url in
                    guard url.isFileURL || url.scheme?.lowercased().hasPrefix("http") == true else { return }
                    store.openExternalURL(url)
                    NSApp.activate(ignoringOtherApps: true)
                }
                // View-level acceptance so an existing window receives links
                // directly; the scene-level matcher below covers cold starts.
                .handlesExternalEvents(preferring: [], allowing: ["http", "https", "file"])
        }
        .windowStyle(.hiddenTitleBar)
        // Links from other apps must land as a tab in an existing window,
        // never as a new window next to it: declaring the schemes this
        // scene handles makes SwiftUI route them to a window that's
        // already there instead of opening one.
        .handlesExternalEvents(matching: ["http", "https", "file"])
        // No automatic window-background dragging: with a hidden title bar and
        // full-size content, a press-and-move on any tab background was claimed
        // as a window drag, so the whole window moved instead of the tab. The
        // window stays draggable through the explicit WindowDragView surfaces
        // (empty top-bar / sidebar areas), which call `performDrag`
        // programmatically and are unaffected by this flag.
        .windowBackgroundDragBehavior(.disabled)
        .commands {
            LeanCommands(mainStore: store, updater: updater)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.flushPendingPersist()
            }
        }

        // Each private window gets its own store, and with it its own
        // in-memory cookies and storage: closing the window ends the session.
        WindowGroup("Private Window", id: PrivateWindow.id) {
            PrivateWindowRoot(updater: updater)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.disabled)
        // A private window must not come back at the next launch.
        .restorationBehavior(.disabled)
    }
}

enum PrivateWindow {
    static let id = "private"
}

private struct PrivateWindowRoot: View {
    @StateObject private var store = LeanStore(isPrivateSession: true)
    @ObservedObject var updater: AppUpdater

    var body: some View {
        LeanView(store: store, updater: updater)
            .frame(minWidth: 720, minHeight: 480)
            .ignoresSafeArea(.all)
    }
}
