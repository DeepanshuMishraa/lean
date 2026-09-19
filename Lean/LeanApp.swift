import SwiftUI

@main
struct LeanApp: App {
    @StateObject private var store = LeanStore()

    var body: some Scene {
        WindowGroup {
            LeanView(store: store)
                .frame(minWidth: 720, minHeight: 480)
                .ignoresSafeArea(.all)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            LeanCommands(store: store)
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
