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

    @Test("Keeps third-party scoping instead of dropping the rule")
    func keepsThirdPartyScope() throws {
        let rules = ChromiumAdBlockRuleCompiler.compile(["||ads.example^$third-party"])

        #expect(rules.blockedDomains.isEmpty)
        #expect(rules.networkRules.count == 1)
        let rule = try #require(rules.networkRules.first)
        #expect(rule.kind == .domain)
        #expect(rule.value == "ads.example")
        #expect(rule.thirdParty == 1)
        #expect(!rule.exception)
    }

    @Test("Keeps domain and content-type scoping")
    func keepsDomainAndTypeScope() throws {
        let rules = ChromiumAdBlockRuleCompiler.compile([
            "||cdn.example/ads.js$script,image,domain=news.example|blog.example"
        ])

        #expect(rules.blockedPatterns.isEmpty)
        #expect(rules.networkRules.count == 1)
        let rule = try #require(rules.networkRules.first)
        #expect(rule.kind == .pattern)
        #expect(rule.domains == ["blog.example", "news.example"])
        #expect(rule.types == ["image", "script"])
    }

    @Test("Keeps popup and important flags")
    func keepsPopupAndImportant() throws {
        let rules = ChromiumAdBlockRuleCompiler.compile([
            """
            ||pop.example^$popup
            ||hard.example^$important
            @@||hard.example^$important
            """
        ])

        #expect(rules.networkRules.count == 3)
        let popup = try #require(rules.networkRules.first { $0.value == "pop.example" })
        #expect(popup.popupOnly)
        let block = try #require(rules.networkRules.first { $0.value == "hard.example" && !$0.exception })
        #expect(block.important)
        let exception = try #require(rules.networkRules.first { $0.value == "hard.example" && $0.exception })
        #expect(exception.important)
    }

    @Test("Websocket-only rules are dropped, mixed rules keep other kinds")
    func websocketRulesHandledSafely() {
        let lone = ChromiumAdBlockRuleCompiler.compile(["||sock.example^$websocket"])
        #expect(lone.blockedDomains.isEmpty)
        #expect(lone.networkRules.isEmpty)

        let mixed = ChromiumAdBlockRuleCompiler.compile(["||sock.example^$script,websocket"])
        #expect(mixed.networkRules.count == 1)
        #expect(mixed.networkRules.first?.types == ["script"])
    }

    @Test("Cosmetic-only exceptions never become network allows")
    func cosmeticOnlyExceptionsStayDropped() {
        let rules = ChromiumAdBlockRuleCompiler.compile([
            """
            @@||ads.example^$elemhide
            @@||ads.example^$generichide
            """
        ])

        #expect(rules.allowedDomains.isEmpty)
        #expect(rules.networkRules.isEmpty)
    }

    @Test("Drops match-case rules the case-insensitive matcher cannot honor")
    func dropsMatchCase() {
        let rules = ChromiumAdBlockRuleCompiler.compile([
            """
            ||ads.example^$match-case
            ||cdn.example/ads.js$third-party,match-case
            """
        ])

        #expect(rules.blockedDomains.isEmpty)
        #expect(rules.blockedPatterns.isEmpty)
        #expect(rules.networkRules.isEmpty)
    }

    @Test("Drops strict party rules while keeping plain party scoping")
    func dropsStrictParty() throws {
        let dropped = ChromiumAdBlockRuleCompiler.compile([
            """
            ||strict3.example^$strict3p
            ||strict1.example^$strict1p
            """
        ])
        #expect(dropped.blockedDomains.isEmpty)
        #expect(dropped.networkRules.isEmpty)

        let kept = ChromiumAdBlockRuleCompiler.compile([
            """
            ||ads.example^$third-party
            ||first.example^$first-party
            """
        ])
        #expect(kept.networkRules.count == 2)
        let third = try #require(kept.networkRules.first { $0.value == "ads.example" })
        #expect(third.thirdParty == 1)
        let first = try #require(kept.networkRules.first { $0.value == "first.example" })
        #expect(first.thirdParty == 0)
    }

    @Test("Curated YouTube text compiles to network and cosmetic rules")
    func youtubeTextCompiles() {
        let rules = ChromiumAdBlockRuleCompiler.compile([
            ChromiumAdBlockRuleCompiler.youtubeFilterText
        ])

        #expect(rules.blockedDomains.contains("googleads.g.doubleclick.net"))
        #expect(rules.blockedPatterns.contains("youtube.com/api/stats/ads"))
        #expect(rules.domainSelectors["youtube.com"]?.contains(".ytp-ad-module") == true)
    }

    @Test("Path-scoped anchors never become whole-domain blocks")
    func pathScopedAnchorsStayScoped() {
        // Regression: `||x.com^*/log.json` once compiled to a bare `x.com`
        // domain block, blanking the entire site.
        let rules = ChromiumAdBlockRuleCompiler.compile([
            """
            ||x.com^*/log.json
            ||twitter.com^*/log.json
            ||ads.example^
            """
        ])

        #expect(!rules.blockedDomains.contains("x.com"))
        #expect(!rules.blockedDomains.contains("twitter.com"))
        #expect(rules.blockedDomains.contains("ads.example"))
    }

    @Test("YouTube scriptlet prunes when enabled and is inert otherwise")
    func youtubeScriptlet() {
        let on = PageScripts.youtubeAds(enabled: true)
        #expect(on.contains("youtube\\.com"))
        #expect(on.contains("adPlacements"))
        #expect(on.contains("playerAds"))
        #expect(on.contains("youtubei/v1/player"))
        #expect(on.contains("JSON.parse"))
        #expect(on.contains("ytInitialPlayerResponse"))
        #expect(on.contains("ytp-skip-ad-button"))

        let off = PageScripts.youtubeAds(enabled: false)
        #expect(!off.contains("adPlacements"))
        #expect(!off.contains("JSON.parse"))
    }
}
