import Testing
@testable import Lean

private func triggers(_ rule: [String: Any]) -> [String: Any] {
    rule["trigger"] as? [String: Any] ?? [:]
}

private func action(_ rule: [String: Any]) -> [String: Any] {
    rule["action"] as? [String: Any] ?? [:]
}

private func singleRule(_ text: String) -> [String: Any]? {
    let result = AdBlockFilterConverter.convert(text + "\n")
    return result.rules.first
}

struct AdBlockFilterConverterTests {
    @Test("Domain-anchored network filter becomes a block rule")
    func domainAnchoredBlock() {
        let rule = singleRule("||ads.example.com^")
        #expect(rule != nil)
        #expect(action(rule!)["type"] as? String == "block")
        let urlFilter = triggers(rule!)["url-filter"] as? String ?? ""
        #expect(urlFilter.contains("ads\\.example\\.com"))
    }

    @Test("Exception filter becomes ignore-previous-rules")
    func exceptionFilter() {
        let rule = singleRule("@@||safe.example.com^")
        #expect(rule != nil)
        #expect(action(rule!)["type"] as? String == "ignore-previous-rules")
    }

    @Test("Third-party option maps to load-type")
    func thirdPartyOption() {
        let rule = singleRule("||ads.example.com^$third-party")
        #expect(rule != nil)
        #expect((triggers(rule!)["load-type"] as? [String]) == ["third-party"])
    }

    @Test("Resource types map to WebKit resource-type")
    func resourceTypes() {
        let rule = singleRule("||ads.example.com^$script,image")
        #expect(rule != nil)
        let types = Set(triggers(rule!)["resource-type"] as? [String] ?? [])
        #expect(types == ["script", "image"])
    }

    @Test("Domain scoping maps to if-domain and unless-domain")
    func domainScoping() {
        let included = singleRule("||ads.example.com^$domain=news.example|blog.example")
        #expect((triggers(included!)["if-domain"] as? [String])?.sorted() == ["*blog.example", "*news.example"])

        let excluded = singleRule("||ads.example.com^$domain=~safe.example")
        #expect((triggers(excluded!)["unless-domain"] as? [String]) == ["*safe.example"])
    }

    @Test("Mixed include/exclude domains are skipped")
    func mixedDomainsSkipped() {
        let result = AdBlockFilterConverter.convert("||ads.example.com^$domain=news.example|~safe.example\n")
        #expect(result.rules.isEmpty)
        #expect(result.skippedCount == 1)
    }

    @Test("Cosmetic filter becomes css-display-none")
    func cosmeticFilter() {
        let rule = singleRule("news.example##.ad-banner")
        #expect(rule != nil)
        #expect(action(rule!)["type"] as? String == "css-display-none")
        #expect(action(rule!)["selector"] as? String == ".ad-banner")
        #expect((triggers(rule!)["if-domain"] as? [String]) == ["*news.example"])
    }

    @Test("Global cosmetic filter has no domain scoping")
    func globalCosmetic() {
        let rule = singleRule("##.sponsored-box")
        #expect(rule != nil)
        #expect(triggers(rule!)["if-domain"] == nil)
        #expect(triggers(rule!)["unless-domain"] == nil)
    }

    @Test("Scriptlets, procedural cosmetics, and exceptions are skipped")
    func unsupportedCosmeticsSkipped() {
        let text = """
        example.com##+js(set-cookie, x)
        example.com##.ad:has-text(Sponsored)
        example.com#@#.allowlisted
        example.com##^responseheader(ad)
        """
        let result = AdBlockFilterConverter.convert(text)
        #expect(result.rules.isEmpty)
        #expect(result.skippedCount == 4)
    }

    @Test("Redirect, CSP, and removeparam network rules are skipped")
    func unsupportedNetworkSkipped() {
        let text = """
        ||ads.example.com^$redirect=noop.js
        ||ads.example.com^$csp=script-src 'none'
        ||ads.example.com^$removeparam=utm_source
        /ads\\/banner\\/\\d+/
        """
        let result = AdBlockFilterConverter.convert(text)
        #expect(result.rules.isEmpty)
        #expect(result.skippedCount == 4)
    }

    @Test("Hosts-format lines block the listed server")
    func hostsLine() {
        let rule = singleRule("127.0.0.1 adserver.example.com")
        #expect(rule != nil)
        #expect(action(rule!)["type"] as? String == "block")
    }

    @Test("Comments and duplicates are skipped")
    func commentsAndDuplicates() {
        let text = """
        ! a comment
        [Adblock Plus 2.0]
        ||ads.example.com^
        ||ads.example.com^
        """
        let result = AdBlockFilterConverter.convert(text)
        // The trailing `^` expands to separator-class and end-anchor rules;
        // the repeated line contributes only duplicates.
        #expect(result.rules.count == 2)
        #expect(result.keptCount == 2)
        #expect(result.skippedCount == 4)
    }

    @Test("Negated resource types are skipped, not treated as patterns")
    func negatedResourceSkipped() {
        let result = AdBlockFilterConverter.convert("-ad-manager/$~stylesheet\n")
        #expect(result.rules.isEmpty)
    }

    @Test("Curated YouTube filters convert to WebKit network and cosmetic rules")
    func curatedYouTubeConverts() {
        let result = AdBlockFilterConverter.convert(ContentBlocker.curatedYouTubeFilters + "\n")
        #expect(!result.rules.isEmpty)
        let hasEndpointBlock = result.rules.contains {
            action($0)["type"] as? String == "block"
                && (triggers($0)["url-filter"] as? String ?? "").contains("youtube\\.com/api/stats/ads")
        }
        #expect(hasEndpointBlock)
        let hasSlotHiding = result.rules.contains {
            action($0)["type"] as? String == "css-display-none"
                && (action($0)["selector"] as? String ?? "").contains("ytp-ad-module")
        }
        #expect(hasSlotHiding)
    }

    @Test("Rules chunk under the WebKit per-list limit")
    func chunking() {
        var many: [[String: Any]] = []
        for index in 0..<90_000 {
            many.append([
                "trigger": ["url-filter": "banner\(index)\\.example"],
                "action": ["type": "block"]
            ])
        }
        let chunks = AdBlockFilterConverter.chunk(many)
        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { $0.count <= AdBlockFilterConverter.maxRulesPerList })
    }
}
