import Foundation
import Testing
@testable import Lean

struct FontSettingsTests {
    @Test("Page font CSS overrides page text with the selected font")
    func pageFontCSS() {
        let script = PageScripts.font(.geistMono)

        #expect(script.contains("'Geist Mono', -apple-system"))
        #expect(script.contains("html body *:not(svg):not(svg *)"))
        #expect(!PageScripts.font(.system).contains("font-family"))
    }

    @Test("LeanFontWeight cases map correctly to numeric rawValues")
    func fontWeightNumericValues() {
        #expect(LeanFontWeight.ultraLight.rawValue == 100)
        #expect(LeanFontWeight.thin.rawValue == 200)
        #expect(LeanFontWeight.light.rawValue == 300)
        #expect(LeanFontWeight.regular.rawValue == 400)
        #expect(LeanFontWeight.medium.rawValue == 500)
        #expect(LeanFontWeight.semibold.rawValue == 600)
        #expect(LeanFontWeight.bold.rawValue == 700)
        #expect(LeanFontWeight.heavy.rawValue == 800)
        #expect(LeanFontWeight.black.rawValue == 900)
    }

    @Test("LeanFontWeight closest matching snaps to proper weight")
    func fontWeightClosestMatching() {
        #expect(LeanFontWeight(closestTo: 100) == .ultraLight)
        #expect(LeanFontWeight(closestTo: 140) == .ultraLight)
        #expect(LeanFontWeight(closestTo: 160) == .thin)
        #expect(LeanFontWeight(closestTo: 380) == .regular)
        #expect(LeanFontWeight(closestTo: 520) == .medium)
        #expect(LeanFontWeight(closestTo: 640) == .semibold)
        #expect(LeanFontWeight(closestTo: 710) == .bold)
        #expect(LeanFontWeight(closestTo: 890) == .black)
    }

    @Test("LeanStore initializes with heading and body font weights")
    @MainActor
    func storeFontWeights() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.uiHeadingWeight == .semibold || LeanFontWeight.allCases.contains(store.uiHeadingWeight))
        #expect(store.uiBodyWeight == .regular || LeanFontWeight.allCases.contains(store.uiBodyWeight))

        store.uiHeadingWeight = .bold
        store.uiBodyWeight = .light
        #expect(store.uiHeadingWeight == .bold)
        #expect(store.uiBodyWeight == .light)
    }

    @Test("Heading and body font weights survive a database reopen")
    @MainActor
    func fontWeightsPersistAcrossRestarts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Lean.sqlite3")

        let first = LeanStore(database: try AppDatabase(url: url))
        first.uiHeadingWeight = .black
        first.uiBodyWeight = .thin

        let second = LeanStore(database: try AppDatabase(url: url))
        #expect(second.uiHeadingWeight == .black)
        #expect(second.uiBodyWeight == .thin)
    }
}
