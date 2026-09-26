import Foundation

enum SearchEngine: String, CaseIterable, Identifiable, Codable {
    case google
    case bing
    case duckDuckGo
    case brave
    case ecosia
    case yahoo

    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .duckDuckGo: return "DuckDuckGo"
        case .brave: return "Brave Search"
        case .ecosia: return "Ecosia"
        case .yahoo: return "Yahoo"
        }
    }

    var searchURL: URL? {
        switch self {
        case .google: return URL(string: "https://www.google.com/search")
        case .bing: return URL(string: "https://www.bing.com/search")
        case .duckDuckGo: return URL(string: "https://duckduckgo.com/")
        case .brave: return URL(string: "https://search.brave.com/search")
        case .ecosia: return URL(string: "https://www.ecosia.org/search")
        case .yahoo: return URL(string: "https://search.yahoo.com/search")
        }
    }
}

enum AddressResolver {
    static func resolve(_ input: String, searchEngine: SearchEngine = .google) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let lower = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if lower == "lean://settings" || lower == "settings" || lower == "about:settings" || lower == "chrome://settings" || lower == "lean:settings" || lower.hasPrefix("lean://settings") {
            return URL(string: "lean://settings")
        }

        if let url = webURL(from: value) {
            return url
        }

        var components = searchEngine.searchURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        components?.queryItems = [URLQueryItem(name: "q", value: value)]
        return components?.url
    }

    static func webURL(from value: String) -> URL? {
        if let components = URLComponents(string: value),
           let scheme = components.scheme?.lowercased(),
           ["http", "https", "lean"].contains(scheme),
           components.host != nil {
            return components.url
        }

        // Everything else has to look like a host before it gets a scheme.
        // Matches Search's Address.url(from:) so bare hosts never fall
        // through to the search engine by accident.
        guard !value.contains(" ") else { return nil }
        let head = value.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !head.contains("@") else { return nil } // an email address, not a host
        let host = hostPart(of: String(head))
        guard looksLikeHost(host) else { return nil }
        // A bare IP literal or a LAN/private host almost never has a public
        // certificate, so https there is a connection failure rather than a
        // page. Default those to http; public domains keep https.
        return URL(string: (isLocalHost(host) || isIPv4Literal(host) ? "http://" : "https://") + value)
    }

    /// A local server address with something after the host (a port or a
    /// path, as in `localhost:3000`): always navigation, never search. Bare
    /// `localhost` returns nil so the normal suggestion list (history,
    /// search) still shows for it.
    static func loopbackServerURL(from value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let bare: String
        if let split = text.range(of: "://") {
            bare = String(text[split.upperBound...])
        } else {
            bare = text
        }
        let head = bare.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard head.contains(":") else { return nil }
        guard isLocalHost(hostPart(of: String(head))) else { return nil }
        return webURL(from: text)
    }

    /// An IP literal typed as an address (`100.109.113.4`,
    /// `100.109.113.4:8000/path`, `[fd00::1]:3000`, or with an explicit
    /// http(s) scheme): always navigation, never search — the loopback fast
    /// path's sibling for raw addresses. Anything else returns nil so
    /// domains and search text keep their normal rows.
    static func ipLiteralURL(from value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let bare: String
        if let split = text.range(of: "://") {
            let scheme = text[..<split.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
            bare = String(text[split.upperBound...])
        } else {
            bare = text
        }
        let head = bare.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let host = hostPart(of: String(head))
        guard isIPv4Literal(host) || isIPv6Literal(host) else { return nil }
        return webURL(from: text)
    }

    /// Whether the URL points at this machine's loopback.
    static func isLoopbackURL(_ url: URL) -> Bool {
        guard var host = url.host?.lowercased() else { return false }
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        return isLocalHost(host)
    }

    /// Host before any port, tolerating bracketed IPv6 (`[::1]:3000`).
    private static func hostPart(of head: String) -> String {
        if head.hasPrefix("[") {
            if let end = head.firstIndex(of: "]") {
                return String(head[head.index(after: head.startIndex)..<end])
            }
            return head
        }
        return head.split(separator: ":").first.map(String.init) ?? head
    }

    private static func looksLikeHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" { return true }
        if lower == "::1" || lower == "[::1]" { return true }
        // A bracketed IPv6 literal (`[fd00::1]`, stripped to `fd00::1` by
        // hostPart): always an address, never a search.
        if host.contains(":") { return true }

        // Four numbers is an address on the local network as often as not.
        let numbers = host.split(separator: ".", omittingEmptySubsequences: false)
        if numbers.count == 4, numbers.allSatisfy({ UInt8($0) != nil }) { return true }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        guard labels.allSatisfy({ label in
            !label.isEmpty
                && !label.hasPrefix("-")
                && !label.hasSuffix("-")
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }) else { return false }

        // The last label carries the weight: a dotted thing ending in letters
        // is a domain, a dotted thing ending in digits is a version number.
        let tld = labels[labels.count - 1]
        return tld.count >= 2 && tld.allSatisfy { $0.isLetter }
    }

    /// Hosts on this machine or the local network. Internal so the tab
    /// engine can offer plain-http retries for them.
    static func isLocalHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".localhost") { return true }
        if lower == "::1" || lower == "[::1]" { return true }
        if lower == "0.0.0.0" { return true }
        // Single-label names (`homelab`, `router`) and local-network
        // suffixes never have public certificates. Bare single labels still
        // go to search via looksLikeHost; this covers `name:port`,
        // `name.local`, and explicit-scheme navigations consistently.
        if isLocalSuffixHost(lower) { return true }
        let parts = lower.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else { return false }
        // Entire 127/8 loopback range, plus the private/LAN ranges — only
        // inside the validated four-component IPv4 branch, so public
        // hostnames such as 10.com or 192.168.com keep their public-domain
        // behavior.
        if parts[0] == "127" { return true }
        if lower.hasPrefix("192.168.") || lower.hasPrefix("10.") { return true }
        // 172.16.0.0/12 office and homelab range.
        if parts[0] == "172", let second = UInt8(parts[1]), (16...31).contains(second) { return true }
        // 100.64.0.0/10 carrier-grade NAT — also the Tailscale/ZeroTier
        // range, so `100.109.113.4` is a LAN box, not the public web.
        if parts[0] == "100", let second = UInt8(parts[1]), (64...127).contains(second) { return true }
        // 169.254.0.0/16 link-local.
        if parts[0] == "169", parts[1] == "254" { return true }
        return false
    }

    /// Four decimal octets, e.g. `100.109.113.4` or `8.8.8.8`.
    static func isIPv4Literal(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy({ UInt8($0) != nil })
    }

    /// A bare IPv6 address as produced by hostPart for bracketed input
    /// (`[fd00::1]:3000` → `fd00::1`): hex, colons, and an optional
    /// `%zone`, with at least two colons so `host:port` scraps never match.
    static func isIPv6Literal(_ host: String) -> Bool {
        let addr = host.split(separator: "%").first.map(String.init) ?? host
        guard addr.filter({ $0 == ":" }).count >= 2 else { return false }
        return !addr.isEmpty && addr.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
    }

    /// Hosts that only ever exist on a local network.
    private static func isLocalSuffixHost(_ lower: String) -> Bool {
        // Bracketed IPv6 literals.
        if lower.hasPrefix("[") && lower.hasSuffix("]") {
            let inner = String(lower.dropFirst().dropLast())
            return isLocalIPv6(inner)
        }
        if isLocalIPv6(lower) { return true }
        // `.local` (mDNS/Bonjour), plus the common LAN-only suffixes.
        let localSuffixes = [".local", ".lan", ".home", ".internal", ".intranet", ".corp", ".test", ".invalid"]
        if localSuffixes.contains(where: { lower == String($0.dropFirst()) || lower.hasSuffix($0) }) { return true }
        // A single label with no dots (`homelab`, `printer`) is a LAN name,
        // not a public domain — unless it parses as something else, which
        // callers decide via looksLikeHost.
        if !lower.contains("."), !lower.contains(":"), !lower.isEmpty {
            // `localhost` handled above; anything else single-label is local.
            // Exclude pure version-like numbers already handled elsewhere.
            return true
        }
        return false
    }

    /// IPv6 loopback, link-local (fe80::/10), and unique-local (fc00::/7).
    private static func isLocalIPv6(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "::1" { return true }
        // Strip any %zone identifier before matching the prefix.
        let addr = lower.split(separator: "%").first.map(String.init) ?? lower
        guard addr.contains(":") else { return false }
        if addr.hasPrefix("fe8") || addr.hasPrefix("fe9") || addr.hasPrefix("fea") || addr.hasPrefix("feb") { return true }
        if addr.hasPrefix("fc") || addr.hasPrefix("fd") { return true }
        return false
    }
}
