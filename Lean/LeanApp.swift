import SwiftUI

@main
struct LeanApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = LeanStore()
    @StateObject private var updater = AppUpdater()

    init() {
        // Belt & suspenders with `isInspectable`: enables WebKit developer
        // extras (right-click Inspect Element, Safari remote inspection).
        // Persisted, not just registered: the default must be visible to
        // WebKit helper processes via cfprefsd, and in-memory registration
        // never leaves this process. Scoped to Lean's own domain.
        UserDefaults.standard.set(true, forKey: "WebKitDeveloperExtrasEnabled")
    }

    var body: some Scene {
        WindowGroup {
            LeanView(store: store, updater: updater)
                .frame(minWidth: 720, minHeight: 480)
                .ignoresSafeArea(.all)
        }
        .windowStyle(.hiddenTitleBar)
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
