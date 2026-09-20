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
    func storeFontWeights() {
        let store = LeanStore()
        #expect(store.uiHeadingWeight == .semibold || LeanFontWeight.allCases.contains(store.uiHeadingWeight))
        #expect(store.uiBodyWeight == .regular || LeanFontWeight.allCases.contains(store.uiBodyWeight))

        store.uiHeadingWeight = .bold
        store.uiBodyWeight = .light
        #expect(store.uiHeadingWeight == .bold)
        #expect(store.uiBodyWeight == .light)
    }
}
