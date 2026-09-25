import Foundation
import Testing
import WebKit
@testable import Lean

@MainActor
struct FrameRateTests {
    @Test("Fast pages lift WebKit's 60 fps hold; off never touches the flag")
    func fastLiftRestoreAndUntouched() {
        // One sequence, not separate tests: both touch the shared switch.
        FrameRate.fast = false
        do {
            let preferences = WKPreferences()
            let baseline = FrameRate.prefersNear60(preferences)
            FrameRate.apply(to: preferences)
            #expect(FrameRate.prefersNear60(preferences) == baseline)
        }

        do {
            let preferences = WKPreferences()
            guard let baseline = FrameRate.prefersNear60(preferences) else {
                // This WebKit has no such flag: apply is a safe no-op.
                FrameRate.fast = true
                FrameRate.apply(to: preferences)
                FrameRate.fast = false
                return
            }
            #expect(baseline == true)

            FrameRate.fast = true
            FrameRate.apply(to: preferences)
            #expect(FrameRate.prefersNear60(preferences) == false)

            FrameRate.fast = false
            FrameRate.restoreChanged()
            #expect(FrameRate.prefersNear60(preferences) == true)
        }
        FrameRate.fast = false
    }
}
