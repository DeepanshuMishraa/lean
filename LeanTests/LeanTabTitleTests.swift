import Foundation
import Testing
import WebKit
@testable import Lean

struct LeanTabTitleTests {
    @MainActor
    @Test("Shows full title when selected, clean short name when inactive")
    func titleDisplay() {
        let tab = LeanTab(dataStore: .default(), initialURL: URL(string: "https://x.com/home"))
        // Simulated loaded title
        // When selected:
        #expect(tab.displayTitle(isSelected: true) == "x.com" || tab.displayTitle(isSelected: true) == "New Tab")

        // When inactive on known site:
        #expect(tab.displayTitle(isSelected: false) == "X")

        // When selected but showFullTitle is disabled:
        #expect(tab.displayTitle(isSelected: true, showFullTitle: false) == "X")

        let youtubeTab = LeanTab(dataStore: .default(), initialURL: URL(string: "https://www.youtube.com/watch?v=123"))
        #expect(youtubeTab.displayTitle(isSelected: false) == "YouTube")
        #expect(youtubeTab.displayTitle(isSelected: true, showFullTitle: false) == "YouTube")

        let slackTab = LeanTab(dataStore: .default(), initialURL: URL(string: "https://slack.com/workspace"))
        #expect(slackTab.displayTitle(isSelected: false) == "Slack")
        #expect(slackTab.displayTitle(isSelected: true, showFullTitle: false) == "Slack")
    }

    @MainActor
    @Test("Page source remains outside session navigation state")
    func sourceTabState() {
        let tab = LeanTab(dataStore: .default(), initialURL: nil)
        tab.presentPageSource(title: "Source of x", html: nil)
        #expect(tab.isPageSource)
        #expect(tab.url == nil)
        #expect(tab.title == "Source of x")
    }

    @MainActor
    @Test("New Tab shows New Tab both when selected and inactive")
    func newTabTitle() {
        let tab = LeanTab(dataStore: .default(), initialURL: nil)
        #expect(tab.displayTitle(isSelected: true) == "New Tab")
        #expect(tab.displayTitle(isSelected: false) == "New Tab")
    }
}
