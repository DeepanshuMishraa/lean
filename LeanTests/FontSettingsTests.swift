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
}
