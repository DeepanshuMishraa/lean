import AppKit
import Testing
@testable import Lean

struct LeanWebViewKeyTests {
    private func key(timestamp: TimeInterval, keyCode: UInt16, type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    @Test("The resent event is the event it was given")
    func sameEvent() {
        let event = key(timestamp: 100, keyCode: 0)
        #expect(LeanWebView.same(event, event))
        #expect(LeanWebView.same(event, key(timestamp: 100, keyCode: 0)))
    }

    @Test("A different press is not the same")
    func differentPress() {
        let event = key(timestamp: 100, keyCode: 0)
        #expect(!LeanWebView.same(event, key(timestamp: 101, keyCode: 0)))
        #expect(!LeanWebView.same(event, key(timestamp: 100, keyCode: 1)))
        #expect(!LeanWebView.same(event, key(timestamp: 100, keyCode: 0, type: .keyUp)))
    }
}
