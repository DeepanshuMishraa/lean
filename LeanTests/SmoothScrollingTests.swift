import Testing
@testable import Lean

struct SmoothScrollingTests {
    @Test("Smooth scrolling leaves wheel input native")
    func nativeScrollingScript() {
        let enabled = PageScripts.smoothScrolling(enabled: true)
        let disabled = PageScripts.smoothScrolling(enabled: false)

        #expect(enabled.contains("scroll-behavior: smooth"))
        #expect(!enabled.contains("addEventListener('wheel'"))
        #expect(!disabled.contains("scroll-behavior: smooth"))
    }
}
