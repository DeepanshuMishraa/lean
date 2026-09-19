import Foundation

enum AddressResolver {
    static func resolve(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let url = webURL(from: value) {
            return url
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: value)]
        return components?.url
    }

    private static func webURL(from value: String) -> URL? {
        if let components = URLComponents(string: value),
           let scheme = components.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
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
