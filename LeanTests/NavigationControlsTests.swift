import Foundation
import Testing
import WebKit
@testable import Lean

private enum NavigationTestError: Error {
    case timedOut
}

@MainActor
private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
    // Generous budget: under full-suite parallel load, first tab loads wait
    // behind real extension initialization and WebKit process warmup.
    for _ in 0..<300 {
        if condition() { return }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    throw NavigationTestError.timedOut
}

struct NavigationControlsTests {
    @Test("Back and forward availability follows WebKit history without a refresh")
    @MainActor
    func historyAvailability() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.html")
        let second = directory.appendingPathComponent("second.html")
        try "<title>First</title>".write(to: first, atomically: true, encoding: .utf8)
        try "<title>Second</title>".write(to: second, atomically: true, encoding: .utf8)

        let tab = LeanTab(dataStore: .nonPersistent(), initialURL: first, adBlockingEnabled: false)
        try await waitUntil { tab.url == first && !tab.isLoading }
        #expect(!tab.canGoBack)
        #expect(!tab.canGoForward)

        tab.load(second)
        try await waitUntil { tab.url == second && tab.canGoBack }
        #expect(!tab.canGoForward)

        tab.goBack()
        try await waitUntil { tab.url == first && tab.canGoForward }
        #expect(!tab.canGoBack)
        tab.destroy()
    }
}
