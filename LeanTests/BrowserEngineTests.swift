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
    func cefUnavailableWithoutFramework() throws {
        // Probe a bundle that cannot contain the framework (unit tests run
        // injected into Lean.app, which DOES bundle it — never use .main).
        let emptyDir = FileManager.default.temporaryDirectory
        let empty = try #require(Bundle(url: emptyDir))
        #expect(!CEFIntegration.isAvailable(bundle: empty))
        #expect(CEFIntegration.frameworkURL(bundle: empty) == nil)
    }

    @MainActor
    @Test("New tabs use the booted engine, never a pending selection")
    func newTabsUseBootEngine() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.engineKind == .webKit)
        #expect(store.bootEngineKind == .webKit)
        #expect(!store.needsEngineRestart)
        let tab = store.newTab(url: nil, select: false)
        #expect(tab.engineKind == .webKit)
        // Pending selection must not leak into live tabs.
        store.requestEngineChange(.cef)
        #expect(store.needsEngineRestart)
        let later = store.newTab(url: nil, select: false)
        #expect(later.engineKind == .webKit)
    }

    @MainActor
    @Test("Requesting the booted engine shows no dialog")
    func requestSameEngineIsSilent() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.requestEngineChange(.webKit)
        #expect(!store.isEngineRestartDialogPresented)
        #expect(!store.needsEngineRestart)
    }

    @MainActor
    @Test("Requesting another engine shows the dialog and persists")
    func requestOtherEngineShowsDialog() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.requestEngineChange(.cef)
        #expect(store.engineKind == .cef)
        #expect(store.isEngineRestartDialogPresented)
        #expect(store.needsEngineRestart)
    }

    @MainActor
    @Test("Cancelling reverts to the booted engine and dismisses")
    func cancelRevertsToBootEngine() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.requestEngineChange(.cef)
        store.cancelEngineChange()
        #expect(store.engineKind == .webKit)
        #expect(!store.isEngineRestartDialogPresented)
        #expect(!store.needsEngineRestart)
    }
}
