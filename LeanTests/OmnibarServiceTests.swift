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
