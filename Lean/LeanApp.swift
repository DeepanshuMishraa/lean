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
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && $0.processIdentifier != me
        }
        guard !others.isEmpty else { return }
        for app in others {
            app.terminate()
        }
        // terminate() is async — wait (bounded) for the other instance to
        // actually exit before LeanStore opens the shared sqlite DB, or both
        // processes write session/history keys concurrently.
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if others.allSatisfy(\.isTerminated) { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
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
