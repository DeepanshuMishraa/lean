import Foundation
import WebKit
@testable import Lean

/// Creates a `LeanStore` backed by an isolated temporary database and a
/// non-persistent website data store.
///
/// Never instantiate `LeanStore()` with no arguments in tests: the default
/// initializer opens the real user database (`AppDatabase.openDefault()`),
/// so any tab, history, or settings mutation leaks into the user's actual
/// browser state (stray restored tabs, clobbered preferences).
/// Returns the store plus the temporary directory, which the caller removes.
@MainActor
func makeIsolatedTestStore() throws -> (LeanStore, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let database = try AppDatabase(url: directory.appendingPathComponent("Lean.sqlite3"))
    let store = LeanStore(dataStore: .nonPersistent(), database: database)
    return (store, directory)
}
