import AppKit
import Foundation

final class FaviconService {
    static let shared = FaviconService()

    private let cache = NSCache<NSString, NSImage>()
    private let session: URLSession
    private let lock = NSLock()
    /// In-flight fetches by host: coalesces N simultaneous requests for the
    /// same host (omnibar rows, tab strip, PiP all ask at once) into one
    /// network hit. Completions run on main.
    private var inFlight: [String: [@MainActor @Sendable (NSImage?) -> Void]] = [:]

    private init() {
        self.cache.countLimit = 300
        self.cache.totalCostLimit = 30 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: config)
    }

    /// Cache key shared by reads, writes, and in-flight coalescing: the
    /// host plus the resolved explicit icon. Different pages on one host
    /// declare different icons; a host-only key would hand every waiter
    /// the first answerer's icon and let winners overwrite each other.
    private func key(host: String, url: URL?, explicitURLString: String?) -> String {
        let explicit = explicitURLString.flatMap { URL(string: $0, relativeTo: url)?.absoluteString } ?? ""
        return "\(host)|\(explicit)"
    }

    func cachedFavicon(for url: URL?, explicitURLString: String? = nil) -> NSImage? {
        guard let host = extractHost(from: url) else { return nil }
        return cache.object(forKey: key(host: host, url: url, explicitURLString: explicitURLString) as NSString)
    }

    func loadFavicon(for url: URL?, explicitURLString: String? = nil, completion: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        guard let host = extractHost(from: url) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let flightKey = key(host: host, url: url, explicitURLString: explicitURLString)
        if let cached = cache.object(forKey: flightKey as NSString) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        lock.lock()
        if inFlight[flightKey] != nil {
            inFlight[flightKey]?.append(completion)
            lock.unlock()
            return
        }
        inFlight[flightKey] = [completion]
        lock.unlock()

        let finish: @MainActor @Sendable (NSImage?) -> Void = { [weak self] image in
            guard let self else { return }
            var callbacks: [@MainActor @Sendable (NSImage?) -> Void] = []
            self.lock.lock()
            callbacks = self.inFlight.removeValue(forKey: flightKey) ?? []
            self.lock.unlock()
            if let image {
                let scaled = self.downscaled(image, to: 64)
                // Cost-aware insertion: without a cost, totalCostLimit is
                // dead and the cache is count-limited only.
                let cost = Int(scaled.size.width * scaled.size.height * 4)
                self.cache.setObject(scaled, forKey: flightKey as NSString, cost: cost)
                for cb in callbacks { cb(scaled) }
            } else {
                for cb in callbacks { cb(nil) }
            }
        }

        // 1. Try explicit link tag URL if provided
        if let explicitURLString, let explicitURL = URL(string: explicitURLString, relativeTo: url) {
            fetchImage(from: explicitURL) { image in
                if let image {
                    Task { @MainActor in finish(image) }
                    return
                }

                // 2. Fallback to Google High-Res Favicon CDN
                self.fetchFromCDN(host: host, finish: finish)
            }
            return
        }

        // 2. Fetch directly from Google High-Res Favicon CDN
        fetchFromCDN(host: host, finish: finish)
    }

    private func fetchFromCDN(host: String, finish: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        guard let cdnURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") else {
            Task { @MainActor in finish(nil) }
            return
        }

        fetchImage(from: cdnURL) { image in
            Task { @MainActor in finish(image) }
        }
    }

    private func fetchImage(from url: URL, completion: @escaping @Sendable (NSImage?) -> Void) {
        let task = session.dataTask(with: url) { data, response, error in
            guard let data, error == nil,
                  data.count < 4 * 1024 * 1024,
                  let image = NSImage(data: data) else {
                completion(nil)
                return
            }
            completion(image)
        }
        task.resume()
    }

    /// Cap stored favicons at ~64pt so a 512px+ site icon can't spike memory
    /// (NSCache here is count-limited only without this).
    private func downscaled(_ image: NSImage, to pointSize: CGFloat) -> NSImage {
        let maxPx = pointSize * 2
        guard image.size.width > maxPx || image.size.height > maxPx else { return image }
        let scale = min(maxPx / image.size.width, maxPx / image.size.height)
        let newSize = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let scaled = NSImage(size: newSize)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        scaled.unlockFocus()
        return scaled
    }

    private func extractHost(from url: URL?) -> String? {
        guard let host = url?.host?.lowercased() else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
