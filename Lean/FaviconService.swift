import AppKit
import Foundation

final class FaviconService {
    static let shared = FaviconService()

    private let cache = NSCache<NSString, NSImage>()
    private let session: URLSession

    private init() {
        self.cache.countLimit = 300
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }

    func cachedFavicon(for url: URL?) -> NSImage? {
        guard let host = extractHost(from: url) else { return nil }
        return cache.object(forKey: host as NSString)
    }

    func loadFavicon(for url: URL?, explicitURLString: String? = nil, completion: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        guard let host = extractHost(from: url) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        if let cached = cache.object(forKey: host as NSString) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        // 1. Try explicit link tag URL if provided
        if let explicitURLString, let explicitURL = URL(string: explicitURLString, relativeTo: url) {
            fetchImage(from: explicitURL) { [weak self] image in
                if let image, let self {
                    self.cache.setObject(image, forKey: host as NSString)
                    DispatchQueue.main.async { completion(image) }
                    return
                }

                // 2. Fallback to Google High-Res Favicon CDN
                self?.fetchFromCDN(host: host, completion: completion)
            }
            return
        }

        // 2. Fetch directly from Google High-Res Favicon CDN
        fetchFromCDN(host: host, completion: completion)
    }

    private func isLocalHost(_ host: String) -> Bool {
        host == "localhost" ||
        host.hasSuffix(".local") ||
        host == "127.0.0.1" ||
        host == "::1" ||
        host.hasPrefix("192.168.") ||
        host.hasPrefix("10.") ||
        host.hasPrefix("172.")
    }

    private func fetchFromCDN(host: String, completion: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        guard !isLocalHost(host),
              let cdnURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64&default_icon=none") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        fetchImage(from: cdnURL) { [weak self] image in
            if let image, let self {
                self.cache.setObject(image, forKey: host as NSString)
                DispatchQueue.main.async { completion(image) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func fetchImage(from url: URL, completion: @escaping @Sendable (NSImage?) -> Void) {
        let task = session.dataTask(with: url) { data, response, error in
            guard let data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  data.count != 726, // Reject Google's default fallback globe PNG (726 bytes)
                  let image = NSImage(data: data) else {
                completion(nil)
                return
            }
            completion(image)
        }
        task.resume()
    }

    private func extractHost(from url: URL?) -> String? {
        guard let host = url?.host?.lowercased() else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
