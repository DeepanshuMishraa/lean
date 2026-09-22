import Foundation
import Testing
@testable import Lean

struct YouTubeBlockingTests {
    @Test("Curated filters leave the consent endpoint alone")
    func consentEndpointAllowed() {
        // tpc.googlesyndication.com serves consent/privacy utilities, not
        // ads. Blocking it breaks YouTube playback init ("failed to
        // connect" until retry), so it must never be in our curated list.
        #expect(!ContentBlocker.curatedYouTubeFilters.contains("tpc.googlesyndication"))
    }

    @Test("Disabled scriptlet is a no-op")
    func disabledScriptletNoOp() {
        #expect(PageScripts.youtubeAds(enabled: false) == "void 0;")
    }

    @Test("Scriptlet honors user pauses and scopes auto-resume to ad ends")
    func pauseHandlingMarkers() {
        let script = PageScripts.youtubeAds(enabled: true)
        #expect(script.contains("__leanYtUserPaused"))
        #expect(script.contains("__leanYtLastAdEnd"))
        #expect(script.contains("__leanYtWasAd"))
    }

    @Test("Source HTML is escaped")
    func htmlEscaping() {
        #expect(LeanTab.escapedHTML("<div>&\"</div>") == "&lt;div&gt;&amp;\"&lt;/div&gt;")
    }
}
