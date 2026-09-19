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
    var searchEngine: SearchEngine? = nil
    var isSwitchToTab: Bool = false
    var tabID: UUID? = nil
}

final class OmnibarService {
    static let shared = OmnibarService()

    func suggestions(
        for query: String,
        history: [(url: URL, title: String)] = [],
        openTabs: [(id: UUID, title: String, url: URL)] = [],
        searchEngine: SearchEngine = .google
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
            let matchesTab = lower.count == 1
                ? (tabTitleLower.hasPrefix(lower) || tabHostLower.hasPrefix(lower))
                : (tabTitleLower.contains(lower) || tabHostLower.contains(lower))
            if matchesTab {
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

        // 2. Add matching history entries
        var directMatch: OmnibarSuggestion?
        let historyMatches = history.filter { item in
            let title = item.title.lowercased()
            let host = item.url.host?.lowercased() ?? ""
            let matchesQuery = lower.count == 1
                ? (title.hasPrefix(lower) || host.hasPrefix(lower))
                : (host.contains(lower) || title.contains(lower))
            guard matchesQuery else { return false }

            guard let openTab = openTabs.first(where: {
                $0.url.host?.lowercased().replacingOccurrences(of: "www.", with: "") == item.url.host?.lowercased().replacingOccurrences(of: "www.", with: "")
            }) else {
                return true
            }
            let isHomePage = item.url.path.isEmpty || item.url.path == "/"
            return item.url != openTab.url && !isHomePage
        }
        for item in historyMatches.prefix(5) {
            results.append(OmnibarSuggestion(
                primaryText: item.title.isEmpty ? (item.url.host ?? trimmed) : item.title,
                secondaryText: item.url.host ?? "",
                isSearch: false,
                targetURL: item.url
            ))
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

        // 4. Search suggestion with the selected search engine
        var comp = searchEngine.searchURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        comp?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        if let searchURL = comp?.url {
            results.append(OmnibarSuggestion(
                primaryText: trimmed,
                secondaryText: searchEngine.name,
                isSearch: true,
                targetURL: searchURL,
                searchEngine: searchEngine
            ))
        }

        return results
    }
}
