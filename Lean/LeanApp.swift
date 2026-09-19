import SwiftUI

@main
struct LeanApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.saveSession()
            }
        }
    }
}
