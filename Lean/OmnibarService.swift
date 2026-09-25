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

    /// Memoized suggestions: the views evaluate `suggestions` 3-5x per
    /// render (body + showSuggestions + key handlers), and typing re-renders
    /// per keystroke. Cache hits are a dict lookup; misses do the real work.
    /// The key fingerprints the query and every suggestion target, so a
    /// retitled history entry or a navigated tab cannot reuse stale results;
    /// the TTL only covers rapid re-evaluation of identical inputs.
    private var memo: [String: (results: [OmnibarSuggestion], at: Date)] = [:]
    private let memoTTL: TimeInterval = 2
    private let lock = NSLock()

    func suggestions(
        for query: String,
        history: [(url: URL, title: String)] = [],
        openTabs: [(id: UUID, title: String, url: URL)] = [],
        searchEngine: SearchEngine = .google
    ) -> [OmnibarSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Case-preserving query plus full target fingerprints: lowercasing
        // or counts alone would serve stale rows after a retitle or a tab
        // navigation to a same-shaped target list.
        let historyPrint = history.map { "\($0.url.absoluteString)|\($0.title)" }.joined(separator: "\n")
        let tabsPrint = openTabs.map { "\($0.id.uuidString)|\($0.title)|\($0.url.absoluteString)" }.joined(separator: "\n")
        let cacheKey = "\(trimmed)|\(searchEngine.rawValue)|\(historyPrint.hashValue)|\(tabsPrint.hashValue)"
        lock.lock()
        if let hit = memo[cacheKey], Date().timeIntervalSince(hit.at) < memoTTL {
            let results = hit.results
            lock.unlock()
            return results
        }
        lock.unlock()
        let results = computeSuggestions(trimmed: trimmed, history: history, openTabs: openTabs, searchEngine: searchEngine)
        lock.lock()
        memo[cacheKey] = (results, Date())
        if memo.count > 50 {
            let cutoff = Date().addingTimeInterval(-memoTTL)
            memo = memo.filter { $0.value.at > cutoff }
        }
        lock.unlock()
        return results
    }

    private func computeSuggestions(
        trimmed: String,
        history: [(url: URL, title: String)],
        openTabs: [(id: UUID, title: String, url: URL)],
        searchEngine: SearchEngine
    ) -> [OmnibarSuggestion] {
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

        // A loopback server with something after the host (localhost:3000)
        // is never a search: one row that opens the server, nothing else —
        // no history, no search-engine row. Bare "localhost" keeps the
        // normal list below.
        if let serverURL = AddressResolver.loopbackServerURL(from: trimmed) {
            return [OmnibarSuggestion(
                primaryText: serverURL.absoluteString,
                secondaryText: "Open local server",
                isSearch: false,
                targetURL: serverURL
            )]
        }

        // Suggest Lean Settings if query matches settings / lean
        if "settings".hasPrefix(lower) || "lean://settings".hasPrefix(lower) || lower == "lean" {
            results.append(OmnibarSuggestion(
                primaryText: "Settings",
                secondaryText: "lean://settings",
                isSearch: false,
                targetURL: URL(string: "lean://settings")!
            ))
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

        // 2. Direct URL for what was typed.
        var directMatch: OmnibarSuggestion?
        if !trimmed.contains(" ") {
            if let url = AddressResolver.webURL(from: trimmed) {
                let host = url.host ?? trimmed
                directMatch = OmnibarSuggestion(
                    primaryText: host,
                    secondaryText: host,
                    isSearch: false,
                    targetURL: url
                )
            }
        }
        // A bare loopback address navigates on Enter even with history
        // about it (e.g. a past search for it): it goes first, the rest
        // still shows.
        let loopbackFirst = directMatch.map { AddressResolver.isLoopbackURL($0.targetURL) } ?? false
        if loopbackFirst, let directMatch {
            results.append(directMatch)
        }

        // 3. Add matching history entries
        // Precompute normalized open-tab hosts once: was O(H*T) with
        // per-item lowercased()+replacingOccurrences inside the filter.
        let openHosts: Set<String> = Set(openTabs.compactMap {
            $0.url.host?.lowercased().replacingOccurrences(of: "www.", with: "")
        })
        let openURLStrings = Set(openTabs.map(\.url))
        let historyMatches = history.filter { item in
            let title = item.title.lowercased()
            let host = item.url.host?.lowercased() ?? ""
            let matchesQuery = lower.count == 1
                ? (title.hasPrefix(lower) || host.hasPrefix(lower))
                : (host.contains(lower) || title.contains(lower))
            guard matchesQuery else { return false }

            let itemHost = item.url.host?.lowercased().replacingOccurrences(of: "www.", with: "") ?? ""
            guard openHosts.contains(itemHost) else { return true }
            // Same host is open: hide exact dupes and homepages, keep rest.
            if openURLStrings.contains(item.url) { return false }
            let isHomePage = item.url.path.isEmpty || item.url.path == "/"
            return !isHomePage
        }
        for item in historyMatches.prefix(5) {
            results.append(OmnibarSuggestion(
                primaryText: item.title.isEmpty ? (item.url.host ?? trimmed) : item.title,
                secondaryText: item.url.host ?? "",
                isSearch: false,
                targetURL: item.url
            ))
        }

        // 4. Fallback for domain-like input is computed above (2.); a
        // non-loopback direct navigation goes here, after history.
        if !loopbackFirst, let directMatch {
            results.append(directMatch)
        }

        // 5. Search suggestion with the selected search engine
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
