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

    @Test("Curated YouTube text compiles to network and cosmetic rules")
    func youtubeTextCompiles() {
        let rules = ChromiumAdBlockRuleCompiler.compile([
            ChromiumAdBlockRuleCompiler.youtubeFilterText
        ])

        #expect(rules.blockedDomains.contains("googleads.g.doubleclick.net"))
        #expect(rules.blockedPatterns.contains("youtube.com/api/stats/ads"))
        #expect(rules.domainSelectors["youtube.com"]?.contains(".ytp-ad-module") == true)
    }

    @Test("YouTube scriptlet prunes when enabled and is inert otherwise")
    func youtubeScriptlet() {
        let on = PageScripts.youtubeAds(enabled: true)
        #expect(on.contains("youtube\\.com"))
        #expect(on.contains("adPlacements"))
        #expect(on.contains("playerAds"))
        #expect(on.contains("youtubei/v1/player"))
        #expect(on.contains("JSON.parse"))
        #expect(on.contains("ytp-skip-ad-button"))

        let off = PageScripts.youtubeAds(enabled: false)
        #expect(!off.contains("adPlacements"))
        #expect(!off.contains("JSON.parse"))
    }
}
