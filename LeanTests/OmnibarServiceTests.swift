import Foundation
import Testing
@testable import Lean

struct OmnibarServiceTests {
    @Test("Suggests matching history before search")
    func suggestsMatchingHistory() {
        let history = [(url: URL(string: "https://example.com/sigma")!, title: "Sigma")]
        let suggestions = OmnibarService.shared.suggestions(for: "sig", history: history)
        #expect(suggestions.first?.primaryText == "Sigma")
        #expect(suggestions.first?.isSearch == false)

        let searchSuggestion = suggestions.first { $0.isSearch }
        #expect(searchSuggestion?.primaryText == "sig")
        #expect(searchSuggestion?.secondaryText == "Google")
    }

    @Test("Suggests direct domain when typing domain")
    func suggestsDomain() {
        let suggestions = OmnibarService.shared.suggestions(for: "officecommun.com")
        #expect(!suggestions.isEmpty)
        #expect(suggestions.first?.primaryText == "officecommun.com")
        #expect(suggestions.first?.secondaryText == "officecommun.com")
    }

    @Test("Direct localhost suggestion uses http and suppresses search")
    func localhostSuppressesSearch() {
        for query in ["localhost:3000", "http://localhost:3000", "127.0.0.1:3000", "http://127.0.0.1:3000"] {
            let suggestions = OmnibarService.shared.suggestions(for: query)
            #expect(!suggestions.isEmpty, "expected suggestions for \(query)")
            let direct = suggestions.first
            #expect(direct?.isSearch == false, "first suggestion for \(query) should navigate, got \(String(describing: direct))")
            #expect(direct?.targetURL.scheme == "http", "expected http for \(query), got \(String(describing: direct?.targetURL))")
            #expect(suggestions.allSatisfy { !$0.isSearch }, "no search suggestion expected for \(query)")
        }
    }

    @Test("Loopback query hides non-loopback history like past engine searches")
    func localhostHidesSearchEngineHistory() {
        let pollutedHistory = [
            (url: URL(string: "https://duckduckgo.com/?q=http%3A%2F%2Flocalhost%3A3000")!, title: "http://localhost:3000 at DuckDuckGo"),
            (url: URL(string: "http://localhost:3000/")!, title: "localhost:3000 · My App"),
        ]
        let suggestions = OmnibarService.shared.suggestions(for: "localhost:3000", history: pollutedHistory)
        #expect(suggestions.allSatisfy { !$0.isSearch })
        #expect(!suggestions.contains { $0.targetURL.host == "duckduckgo.com" })
        #expect(suggestions.contains { $0.targetURL.absoluteString == "http://localhost:3000/" })
        #expect(suggestions.first?.targetURL.scheme == "http")
    }
    @Test("Non-loopback domains still offer search")
    func domainKeepsSearch() {
        let suggestions = OmnibarService.shared.suggestions(for: "officecommun.com")
        #expect(suggestions.contains { $0.isSearch })
    }
    @Test("Does not invent a dot-com URL for plain search text")
    func doesNotInventDotComURL() {
        let suggestions = OmnibarService.shared.suggestions(for: "hello")

        #expect(suggestions.count == 1)
        #expect(suggestions.first?.isSearch == true)
        #expect(suggestions.first?.primaryText == "hello")
    }

    @Test("Rejects empty query with no open tabs")
    func rejectsEmptyWithNoTabs() {
        let suggestions = OmnibarService.shared.suggestions(for: "   ")
        #expect(suggestions.isEmpty)
    }

    @Test("Recommends open tabs when query is empty")
    func recommendsOpenTabsWhenEmpty() {
        let tabID1 = UUID()
        let tabID2 = UUID()
        let openTabs = [
            (id: tabID1, title: "GitHub", url: URL(string: "https://github.com")!),
            (id: tabID2, title: "YouTube", url: URL(string: "https://youtube.com")!)
        ]

        let suggestions = OmnibarService.shared.suggestions(for: "", openTabs: openTabs)
        #expect(suggestions.count == 2)
        #expect(suggestions[0].primaryText == "GitHub")
        #expect(suggestions[0].isSwitchToTab == true)
        #expect(suggestions[0].tabID == tabID1)
        #expect(suggestions[1].primaryText == "YouTube")
        #expect(suggestions[1].isSwitchToTab == true)
        #expect(suggestions[1].tabID == tabID2)
    }

    @Test("Matches open tabs when query is entered")
    func matchesOpenTabsWithQuery() {
        let tabID = UUID()
        let openTabs = [
            (id: tabID, title: "Cloudflare Dashboard", url: URL(string: "https://dash.cloudflare.com")!)
        ]

        let suggestions = OmnibarService.shared.suggestions(for: "cloud", openTabs: openTabs)
        let tabMatch = suggestions.first { $0.isSwitchToTab }
        #expect(tabMatch != nil)
        #expect(tabMatch?.primaryText == "Cloudflare Dashboard")
        #expect(tabMatch?.tabID == tabID)
    }
}
