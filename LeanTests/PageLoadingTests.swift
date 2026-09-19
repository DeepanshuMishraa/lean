import Testing
@testable import Lean

struct PageLoadingTests {
    @Test("Loader waits for DOM content and the first rendered frame")
    func pageReadyScript() {
        let script = PageScripts.pageReady

        #expect(script.contains("DOMContentLoaded"))
        #expect(script.components(separatedBy: "requestAnimationFrame").count == 3)
        #expect(script.contains("messageHandlers.pageReady"))
    }
}
