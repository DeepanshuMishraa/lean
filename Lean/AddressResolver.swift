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

    private static func webURL(from value: String) -> URL? {
        if let components = URLComponents(string: value),
           let scheme = components.scheme?.lowercased(),
           ["http", "https", "lean"].contains(scheme),
           components.host != nil {
            return components.url
        }

        let looksLikeHost = !value.contains(" ") && (
            value.contains(".") ||
            value.hasPrefix("localhost") ||
            value.range(of: #"^\d{1,3}(\.\d{1,3}){3}(:\d+)?(/.*)?$"#, options: .regularExpression) != nil
        )
        guard looksLikeHost else { return nil }
        return URLComponents(string: "https://\(value)")?.url
    }
}
