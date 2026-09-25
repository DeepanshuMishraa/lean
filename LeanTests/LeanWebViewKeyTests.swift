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

    @Test("Two presses whose replies arrive later are both recognized")
    func lateReplies() {
        var tracker = OutstandingKeys(capacity: 16)
        let first = key(timestamp: 100, keyCode: 0)
        let second = key(timestamp: 101, keyCode: 1)
        let gotFirst = tracker.received(first)
        let gotSecond = tracker.received(second)
        #expect(gotFirst == false)
        #expect(gotSecond == false)
        // The earlier press's reply arrives after the newer press: still
        // recognized, not mistaken for a new press.
        let replyFirst = tracker.received(first)
        let replySecond = tracker.received(second)
        #expect(replyFirst == true)
        #expect(replySecond == true)
        // Consumed replies never repeat.
        let again = tracker.received(first)
        #expect(again == false)
    }

    @Test("Capacity bounds presses whose replies never come")
    func bounded() {
        var tracker = OutstandingKeys(capacity: 2)
        let first = key(timestamp: 100, keyCode: 0)
        let r1 = tracker.received(first)
        let r2 = tracker.received(key(timestamp: 101, keyCode: 1))
        let r3 = tracker.received(key(timestamp: 102, keyCode: 2))
        #expect(r1 == false)
        #expect(r2 == false)
        #expect(r3 == false)
        // Evicted long ago: reads as new rather than growing without limit.
        let r4 = tracker.received(first)
        #expect(r4 == false)
    }
}
