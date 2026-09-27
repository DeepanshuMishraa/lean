import Testing
@testable import Lean

/// The password-field tracker installs a capture-phase scroll listener in
/// every main frame. It must stay off the scroll path unless a credential
/// field is focused — per-scroll layouts plus bridge messages made momentum
/// scrolling on huge streaming pages stutter.
struct PasswordFieldFocusTests {
    @Test("Scroll stays free unless a credential field is focused")
    func scrollEarlyOut() {
        let script = PageScripts.passwordFieldFocus
        #expect(script.contains("if (!activeField) return"))
        #expect(script.contains("document.addEventListener('scroll'"))
    }

    @Test("Reports only move the overlay on real rect changes")
    func reportDedup() {
        let script = PageScripts.passwordFieldFocus
        #expect(script.contains("if (key === lastKey) return"))
        #expect(script.contains("document.contains(activeField)"))
    }

    @Test("Tracks the focused field across focus hops")
    func focusTracking() {
        let script = PageScripts.passwordFieldFocus
        #expect(script.contains("activeField = el"))
        #expect(script.contains("activeElement"))
        #expect(script.contains(PageScripts.passwordFieldMessageName))
    }
}
