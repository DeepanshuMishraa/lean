import AppKit
import SwiftUI

@main
struct LeanApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: LeanStore
    @StateObject private var updater: AppUpdater

    init() {
        // Single instance: a stale duplicate (e.g. left behind by an engine
        // restart) shares the profile DB and its window can overlap ours.
        Self.terminateDuplicates()
        _store = StateObject(wrappedValue: LeanStore())
        _updater = StateObject(wrappedValue: AppUpdater())
    }

    private static func terminateDuplicates() {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for app in NSWorkspace.shared.runningApplications
            where app.bundleIdentifier == bundleID && app.processIdentifier != me {
            app.terminate()
        }
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
