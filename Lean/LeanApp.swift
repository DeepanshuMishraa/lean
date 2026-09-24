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
        }
        .windowStyle(.hiddenTitleBar)
        // No automatic window-background dragging: with a hidden title bar and
        // full-size content, a press-and-move on any tab background was claimed
        // as a window drag, so the whole window moved instead of the tab. The
        // window stays draggable through the explicit WindowDragView surfaces
        // (empty top-bar / sidebar areas), which call `performDrag`
        // programmatically and are unaffected by this flag.
        .windowBackgroundDragBehavior(.disabled)
        .commands {
            LeanCommands(store: store, updater: updater)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.saveSession()
            }
        }
    }
}
