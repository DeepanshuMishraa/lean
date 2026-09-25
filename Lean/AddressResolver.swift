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
        // A local server almost never has a certificate, so https there is a
        // connection failure rather than a page.
        return URL(string: (isLocalHost(host) ? "http://" : "https://") + value)
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

    private static func isLocalHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".localhost") { return true }
        if lower == "::1" || lower == "[::1]" { return true }
        if lower == "0.0.0.0" { return true }
        let parts = lower.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) {
            // Entire 127/8 loopback range, plus common LAN ranges.
            if parts[0] == "127" { return true }
            if lower.hasPrefix("192.168.") || lower.hasPrefix("10.") { return true }
        }
        return lower.hasPrefix("192.168.") || lower.hasPrefix("10.")
    }
}
