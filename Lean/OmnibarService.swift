import Foundation

struct OmnibarSuggestion: Identifiable, Equatable {
    var id: String {
        if isSwitchToTab, let tabID {
            return "tab-\(tabID.uuidString)"
        }
        if isSearch {
            return "search-\(primaryText)"
        }
        return "url-\(targetURL.absoluteString)-\(primaryText)"
    }
    let primaryText: String
    let secondaryText: String
    let isSearch: Bool
    let targetURL: URL
    var isSwitchToTab: Bool = false
    var tabID: UUID? = nil
}

final class OmnibarService {
    static let shared = OmnibarService()

    private let knownSites: [(domain: String, title: String, keywords: [String])] = [
        ("officecommun.com", "Office Commun", ["off", "office", "commun", "officecommun"]),
        ("x.com", "X", ["x", "twitter", "twt"]),
        ("discord.com", "Discord", ["d", "dis", "discord"]),
        ("claude.ai", "Claude", ["c", "cla", "claude", "anthropic"]),
        ("github.com", "GitHub", ["g", "git", "github"]),
        ("slack.com", "Slack", ["s", "sla", "slack"]),
        ("google.com", "Google", ["g", "goog", "google"]),
        ("apple.com", "Apple", ["app", "appl", "apple"]),
        ("youtube.com", "YouTube", ["yt", "you", "youtube"]),
        ("figma.com", "Figma", ["fig", "figma"]),
        ("reddit.com", "Reddit", ["red", "reddit"]),
        ("news.ycombinator.com", "Hacker News", ["hn", "hacker", "ycombinator"])
    ]

    func suggestions(
        for query: String,
        history: [(url: URL, title: String)] = [],
        openTabs: [(id: UUID, title: String, url: URL)] = []
    ) -> [OmnibarSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        var results: [OmnibarSuggestion] = []

        // If query is empty, recommend other open tabs (matching user reference screenshot)
        if trimmed.isEmpty {
            for tab in openTabs {
                results.append(OmnibarSuggestion(
                    primaryText: tab.title.isEmpty ? (tab.url.host ?? "Tab") : tab.title,
                    secondaryText: tab.url.host ?? "",
                    isSearch: false,
                    targetURL: tab.url,
                    isSwitchToTab: true,
                    tabID: tab.id
                ))
            }
            return results
        }

        // 1. Check open tabs matching query
        for tab in openTabs {
            let tabTitleLower = tab.title.lowercased()
            let tabHostLower = tab.url.host?.lowercased() ?? ""
            if tabTitleLower.contains(lower) || tabHostLower.contains(lower) {
                results.append(OmnibarSuggestion(
                    primaryText: tab.title.isEmpty ? (tab.url.host ?? "Tab") : tab.title,
                    secondaryText: tab.url.host ?? "",
                    isSearch: false,
                    targetURL: tab.url,
                    isSwitchToTab: true,
                    tabID: tab.id
                ))
            }
        }

        // 2. Direct match from known sites
        var directMatch: OmnibarSuggestion?

        if let site = knownSites.first(where: {
            $0.domain.lowercased().hasPrefix(lower) ||
            $0.title.lowercased().hasPrefix(lower) ||
            $0.keywords.contains { $0.lowercased().hasPrefix(lower) }
        }) {
            if let url = URL(string: "https://\(site.domain)") {
                directMatch = OmnibarSuggestion(
                    primaryText: site.domain,
                    secondaryText: site.title,
                    isSearch: false,
                    targetURL: url
                )
            }
        }

        // 2. Check history
        if directMatch == nil {
            if let item = history.first(where: {
                ($0.url.host?.lowercased().contains(lower) == true) ||
                $0.title.lowercased().contains(lower)
            }) {
                let host = item.url.host ?? trimmed
                directMatch = OmnibarSuggestion(
                    primaryText: host,
                    secondaryText: item.title,
                    isSearch: false,
                    targetURL: item.url
                )
            }
        }

        // 3. Fallback for domain-like input
        if directMatch == nil && !trimmed.contains(" ") {
            if trimmed.contains(".") || trimmed.hasPrefix("localhost") {
                let urlString = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
                    ? trimmed
                    : "https://\(trimmed)"
                if let url = URL(string: urlString) {
                    let host = url.host ?? trimmed
                    directMatch = OmnibarSuggestion(
                        primaryText: host,
                        secondaryText: host,
                        isSearch: false,
                        targetURL: url
                    )
                }
            }
        }

        if let directMatch {
            results.append(directMatch)
        }

        // 4. Search suggestion with Google
        var comp = URLComponents(string: "https://www.google.com/search")
        comp?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        if let searchURL = comp?.url {
            results.append(OmnibarSuggestion(
                primaryText: trimmed,
                secondaryText: "Google",
                isSearch: true,
                targetURL: searchURL
            ))
        }

        return results
    }
}
