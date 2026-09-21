import Foundation
import Testing
@testable import Lean

struct BrowserEngineKindTests {
    @Test("Defaults to WebKit for unknown values")
    func defaultsToWebKit() {
        #expect(BrowserEngineKind(rawValue: "bogus") == nil)
        let kind = BrowserEngineKind(rawValue: "bogus") ?? .webKit
        #expect(kind == .webKit)
    }

    @Test("CEF framework probe is false without a bundled framework")
    func cefUnavailableByDefault() {
        #expect(!CEFIntegration.isAvailable())
    }

    @MainActor
    @Test("New tabs inherit the store engine choice, default WebKit")
    func newTabsInheritEngine() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.engineKind == .webKit)
        let tab = store.newTab(url: nil, select: false)
        #expect(tab.engineKind == .webKit)
        store.engineKind = .cef
        let cefTab = store.newTab(url: nil, select: false)
        #expect(cefTab.engineKind == .cef)
        // Existing tabs never hot-swap engines.
        #expect(tab.engineKind == .webKit)
    }
}
