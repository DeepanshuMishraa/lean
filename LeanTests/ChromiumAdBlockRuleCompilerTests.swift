import Testing
@testable import Lean

struct ChromiumAdBlockRuleCompilerTests {
    @Test("Compiles fast network rules and supported cosmetic selectors")
    func compilesSupportedRules() {
        let rules = ChromiumAdBlockRuleCompiler.compile([
            """
            ||ads.example^
            @@||allowed.ads.example^
            0.0.0.0 tracker.example
            plain/ad/script.js
            example.com##.sponsored
            ##[data-ad-slot]
            example.com#@#.allowed-ad
            ##+js(abort-on-property-read, adblock)
            """
        ])

        #expect(rules.blockedDomains == ["ads.example", "tracker.example"])
        #expect(rules.allowedDomains == ["allowed.ads.example"])
        #expect(rules.blockedPatterns == ["plain/ad/script.js"])
        #expect(rules.globalSelectors == ["[data-ad-slot]"])
        #expect(rules.domainSelectors["example.com"] == [".sponsored"])
    }

    @Test("Exceptions remove matching blocking rules")
    func exceptionsWin() {
        let rules = ChromiumAdBlockRuleCompiler.compile([
            """
            ||ads.example^
            @@||ads.example^
            tracking/pixel
            @@tracking/pixel
            """
        ])

        #expect(rules.blockedDomains.isEmpty)
        #expect(rules.blockedPatterns.isEmpty)
    }

    @Test("Keeps path-scoped rules out of the domain matcher")
    func preservesPathScope() {
        let rules = ChromiumAdBlockRuleCompiler.compile(["||cdn.example/ads/banner.js"])

        #expect(rules.blockedDomains.isEmpty)
        #expect(rules.blockedPatterns == ["cdn.example/ads/banner.js"])
    }

    @Test("Domain-scoped cosmetic exceptions do not clear global selectors")
    func scopedCosmeticExceptionsStayScoped() {
        let rules = ChromiumAdBlockRuleCompiler.compile([
            """
            ##.ad
            example.com##.ad
            example.com#@#.ad
            other.com##.ad
            """
        ])

        #expect(rules.globalSelectors == [".ad"])
        #expect(rules.domainSelectors["example.com"] == nil)
        #expect(rules.domainSelectors["other.com"] == [".ad"])
    }

    @Test("Skips unsupported procedural cosmetics and risky patterns")
    func skipsUnsupportedRules() {
        let rules = ChromiumAdBlockRuleCompiler.compile([
            """
            example.com##div:has-text(Advertisement)
            ||ads.example^$redirect=noopjs
            /^https?:\\/\\/ads\\./
            """
        ])

        #expect(rules.blockedDomains.isEmpty)
        #expect(rules.blockedPatterns.isEmpty)
        #expect(rules.domainSelectors.isEmpty)
    }
}
