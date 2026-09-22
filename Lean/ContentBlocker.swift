import Foundation
import WebKit

/// Built-in tracker & ad filtering backed by uBlock Origin filter lists.
///
/// Lean is a WebKit browser, so extensions can't run here; instead the same
/// upstream lists (EasyList, EasyPrivacy, uBlock filters incl. privacy,
/// unbreak and quick-fixes, Peter Lowe's) are fetched weekly, converted to
/// `WKContentRuleList` JSON with `AdBlockFilterConverter`, and attached to
/// every tab.
@MainActor
enum ContentBlocker {
    struct FilterSource: Sendable {
        var id: String
        var url: URL
        var minBytes: Int
    }

    static let filterSources: [FilterSource] = [
        FilterSource(
            id: "easylist",
            url: URL(string: "https://easylist.to/easylist/easylist.txt")!,
            minBytes: 10_000
        ),
        FilterSource(
            id: "easyprivacy",
            url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
            minBytes: 10_000
        ),
        FilterSource(
            id: "ublock-filters",
            url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt")!,
            minBytes: 5_000
        ),
        FilterSource(
            id: "ublock-badware",
            url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/badware.txt")!,
            minBytes: 1_000
        ),
        FilterSource(
            id: "ublock-privacy",
            url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy.txt")!,
            minBytes: 1_000
        ),
        FilterSource(
            id: "ublock-unbreak",
            url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt")!,
            minBytes: 1_000
        ),
        FilterSource(
            id: "ublock-quick-fixes",
            url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/quick-fixes.txt")!,
            minBytes: 500
        ),
        FilterSource(
            id: "peter-lowe",
            url: URL(string: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext")!,
            minBytes: 1_000
        ),
    ]

    /// Curated YouTube coverage. In-stream ads are same-origin
    /// (`youtube.com`, `googlevideo.com`) with dynamic paths and JS-injected
    /// creatives, so generic list rules structurally miss them: uBO handles
    /// this with scriptlets/redirects, which WebKit cannot run natively.
    /// These endpoint blocks + ad-slot cosmetics cover the observable ad
    /// surface; the player-response pruning scriptlet keeps the player out
    /// of ad mode entirely.
    static let curatedYouTubeFilters = """
    ||googleads.g.doubleclick.net^
    ||static.doubleclick.net^
    ||tpc.googlesyndication.com^
    ||youtube.com/api/stats/ads
    ||youtube.com/pagead/
    ||youtube.com/ptracking
    ||s.youtube.com^
    youtube.com##.ytp-ad-module
    youtube.com##.ytp-ad-player-overlay
    youtube.com##.ytp-ad-text
    youtube.com##.ytp-ad-message-container
    youtube.com##.ytp-ad-image-overlay
    youtube.com###player-ads
    youtube.com##ytd-ad-slot-renderer
    youtube.com##ytd-display-ad-renderer
    youtube.com##ytd-promoted-sparkles-web-renderer
    youtube.com##ytd-in-feed-ad-layout-renderer
    youtube.com###masthead-ad
    youtube.com##ytd-search-pyv-renderer
    youtube.com##ytd-companion-slot-renderer
    youtube.com##.ytp-ad-overlay-container
    youtube.com##.ytp-featured-product
    """

    static let updateInterval: TimeInterval = 7 * 24 * 60 * 60
    static let didUpdateNotification = Notification.Name("LeanAdBlockFiltersUpdated")

    private static let listIdentifierPrefix = "com.dipxsy.lean.blocker"
    private static let lastUpdatedKey = "adBlockFiltersLastUpdated"
    private static let ruleCountKey = "adBlockFiltersRuleCount"
    /// Bump when the bundled input changes (curated lists, converter
    /// semantics) so existing installs recompile once instead of waiting
    /// for the weekly refresh.
    private static let schemaVersionKey = "adBlockFiltersSchemaVersion"
    private static let currentSchemaVersion = 3
    private static let maxStoredLists = 8

    private static var cachedRuleLists: [WKContentRuleList] = []
    private static var loadTask: Task<[WKContentRuleList], Never>?
    private static var refreshTask: Task<Void, Never>?

    /// Compiled rule lists, from WebKit's store or the offline fallback.
    /// Call `refreshIfNeeded()` separately (e.g. at launch) to update lists.
    static func ruleLists() async -> [WKContentRuleList] {
        if !cachedRuleLists.isEmpty {
            return cachedRuleLists
        }
        if let loadTask {
            return await loadTask.value
        }

        let task = Task {
            let stored = await loadStoredRuleLists()
            if !stored.isEmpty {
                return stored
            }

            let texts = loadCachedFilterTexts()
            if !texts.isEmpty {
                let compiled = await compile(texts: Array(texts.values) + [curatedYouTubeFilters])
                if !compiled.isEmpty {
                    return compiled
                }
            }
            return await compile(texts: [fallbackFilterText, curatedYouTubeFilters])
        }
        loadTask = task
        let lists = await task.value
        loadTask = nil
        cachedRuleLists = lists
        return lists
    }

    /// Backwards-compatible single-list accessor (first chunk).
    static func ruleList() async -> WKContentRuleList? {
        await ruleLists().first
    }

    /// Fetch fresh lists when the cache is older than `updateInterval`.
    static func refreshIfNeeded() {
        guard refreshTask == nil else { return }
        let schemaVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        if schemaVersion >= currentSchemaVersion {
            let lastUpdated = lastUpdatedDate
            let cached = loadCachedFilterTexts()
            let hasEverySource = filterSources.allSatisfy { cached[$0.id] != nil }
            if hasEverySource,
               let lastUpdated,
               Date().timeIntervalSince(lastUpdated) < updateInterval {
                return
            }
        }
        refreshTask = Task {
            defer { refreshTask = nil }
            await refreshNow()
        }
    }

    struct RefreshResult: Sendable {
        var ruleCount: Int
        var listCount: Int
        var updatedSources: Int
    }

    /// Fetch, convert, persist, and compile all filter lists.
    /// Individual source failures fall back to cached text; total failure keeps the old lists.
    @discardableResult
    static func refreshNow() async -> RefreshResult? {
        let cached = loadCachedFilterTexts()
        var fresh: [String: String] = [:]

        await withTaskGroup(of: (String, String?).self) { group in
            for source in filterSources {
                group.addTask {
                    let text = await fetchFilterText(from: source)
                    return (source.id, text)
                }
            }
            for await (id, text) in group {
                if let text {
                    fresh[id] = text
                }
            }
        }

        // Merge fresh downloads over cached texts so one failed host can't wipe coverage.
        var merged = cached
        for (id, text) in fresh {
            merged[id] = text
        }
        guard !merged.isEmpty else { return nil }

        let texts = filterSources.compactMap { merged[$0.id] }
        let encoded = await encode(texts: texts)
        guard !encoded.json.isEmpty else { return nil }

        persistFilterTexts(merged)
        let compiled = await compile(encoded: encoded.json)
        guard !compiled.isEmpty else { return nil }

        cachedRuleLists = compiled
        UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
        lastUpdatedDate = Date()
        cachedRuleCount = encoded.keptCount
        NotificationCenter.default.post(name: didUpdateNotification, object: nil)
        return RefreshResult(
            ruleCount: encoded.keptCount,
            listCount: compiled.count,
            updatedSources: fresh.count
        )
    }

    static var lastUpdatedDate: Date? {
        get {
            let stamp = UserDefaults.standard.double(forKey: lastUpdatedKey)
            guard stamp > 0 else { return nil }
            return Date(timeIntervalSince1970: stamp)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastUpdatedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastUpdatedKey)
            }
        }
    }

    static var cachedRuleCount: Int {
        get { UserDefaults.standard.integer(forKey: ruleCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: ruleCountKey) }
    }

    // MARK: - Fetching

    private static func fetchFilterText(from source: FilterSource) async -> String? {
        do {
            var request = URLRequest(
                url: source.url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 30
            )
            request.setValue("Lean/1.0 (macOS; WebKit content blocker)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard data.count >= source.minBytes else { return nil }
            let text = String(decoding: data, as: UTF8.self)
            guard text.contains("\n") else { return nil }
            return text
        } catch {
            return nil
        }
    }

    // MARK: - Disk cache

    private static func filtersDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("Lean/AdBlockFilters", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func loadCachedFilterTexts() -> [String: String] {
        guard let directory = filtersDirectory() else { return [:] }
        var texts: [String: String] = [:]
        for source in filterSources {
            let file = directory.appendingPathComponent("\(source.id).txt")
            if let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty {
                texts[source.id] = text
            }
        }
        return texts
    }

    private static func persistFilterTexts(_ texts: [String: String]) {
        guard let directory = filtersDirectory() else { return }
        for (id, text) in texts {
            let file = directory.appendingPathComponent("\(id).txt")
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Compilation

    private struct EncodedRules: Sendable {
        var json: [String]
        var keptCount: Int
    }

    private static func loadStoredRuleLists() async -> [WKContentRuleList] {
        guard let store = WKContentRuleListStore.default() else { return [] }
        var lists: [WKContentRuleList] = []
        for index in 0..<maxStoredLists {
            guard let list = try? await store.contentRuleList(
                forIdentifier: "\(listIdentifierPrefix).\(index)"
            ) else { break }
            lists.append(list)
        }
        return lists
    }

    private static func encode(texts: [String]) async -> EncodedRules {
        let listLimit = maxStoredLists
        return await Task.detached(priority: .utility) {
            let combined = texts.joined(separator: "\n")
            guard !combined.isEmpty else { return EncodedRules(json: [], keptCount: 0) }
            let conversion = AdBlockFilterConverter.convert(combined)
            let json = AdBlockFilterConverter.chunk(conversion.rules)
                .prefix(listLimit)
                .compactMap { chunk -> String? in
                    guard let data = try? JSONSerialization.data(withJSONObject: chunk) else { return nil }
                    return String(data: data, encoding: .utf8)
                }
            return EncodedRules(json: json, keptCount: conversion.keptCount)
        }.value
    }

    private static func compile(texts: [String]) async -> [WKContentRuleList] {
        let encoded = await encode(texts: texts)
        return await compile(encoded: encoded.json)
    }

    private static func compile(encoded: [String]) async -> [WKContentRuleList] {
        guard let store = WKContentRuleListStore.default() else { return [] }
        var compiled: [WKContentRuleList] = []
        for (index, json) in encoded.enumerated() {
            let identifier = "\(listIdentifierPrefix).\(index)"
            if let list = try? await compile(identifier: identifier, json: json, store: store) {
                compiled.append(list)
            }
        }
        // Drop stale chunks from a previously larger split.
        for index in compiled.count..<maxStoredLists {
            try? await store.removeContentRuleList(forIdentifier: "\(listIdentifierPrefix).\(index)")
        }
        return compiled
    }

    private static func compile(
        identifier: String,
        json: String,
        store: WKContentRuleListStore
    ) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) { ruleList, error in
                if let ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: error ?? ContentBlockerError.compilationFailed)
                }
            }
        }
    }

    // MARK: - Offline fallback

    /// High-signal network rules used before the first successful list download.
    /// Replaced by full uBlock Origin lists as soon as any fetch succeeds.
    private static let fallbackFilterText = """
    ||doubleclick.net^
    ||googlesyndication.com^
    ||googleadservices.com^
    ||adnxs.com^
    ||amazon-adsystem.com^
    ||criteo.com^
    ||criteo.net^
    ||taboola.com^
    ||outbrain.com^
    ||scorecardresearch.com^
    ||quantserve.com^
    ||adsrvr.org^
    ||2mdn.net^
    ||google-analytics.com^
    ||googletagmanager.com^
    ||hotjar.com^
    ||mixpanel.com^
    ||fullstory.com^
    ||segment.io^$third-party
    ||segment.com^$third-party
    ##.adsbygoogle
    ##[id^='google_ads_']
    ##[class*='ad-container']
    ##[data-ad-slot]
    """
}

private enum ContentBlockerError: Error {
    case compilationFailed
}
