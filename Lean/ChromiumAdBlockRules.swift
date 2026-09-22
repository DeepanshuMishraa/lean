import Foundation

/// A network rule with ABP option scoping intact. The native CEF matcher
/// evaluates the scope per request (frame URL for third-party/domain,
/// CEF resource type for content kinds), so rules carrying `$third-party`,
/// `$domain=`, `$script`, `$popup`, `$important`, … actually enforce instead
/// of being silently dropped.
struct ChromiumNetworkRule: Sendable {
    enum Kind: String, Sendable {
        case domain
        case pattern
    }

    /// Lowercased host (`domain`) or URL substring (`pattern`).
    var value: String
    var kind: Kind
    var exception: Bool
    /// -1 = any party, 0 = first-party only, 1 = third-party only.
    var thirdParty: Int
    /// Request is scoped to these document domains (`domain=` includes).
    var domains: [String]
    /// Request is excluded on these document domains (`~` entries).
    var notDomains: [String]
    /// Normalized content kinds (`script`, `image`, …). Empty = all kinds.
    var types: [String]
    var important: Bool
    /// Only applies to popup navigations (`$popup`).
    var popupOnly: Bool
    /// Never applies to popup navigations (`$~popup`).
    var excludePopup: Bool

    /// Bridge representation for the ObjC++ matcher. Computed (not stored),
    /// so the struct itself stays Sendable.
    var bridgeDictionary: [AnyHashable: Any] {
        [
            "kind": kind.rawValue,
            "value": value,
            "exception": exception,
            "thirdParty": thirdParty,
            "domains": domains,
            "notDomains": notDomains,
            "types": types,
            "important": important,
            "popupOnly": popupOnly,
            "excludePopup": excludePopup,
        ]
    }
}

struct ChromiumAdBlockRules: Sendable {
    var blockedDomains: [String]
    var allowedDomains: [String]
    var blockedPatterns: [String]
    var allowedPatterns: [String]
    var globalSelectors: [String]
    var domainSelectors: [String: [String]]
    /// Scoped network rules (any rule carrying options beyond bare matching).
    var networkRules: [ChromiumNetworkRule]
}

enum ChromiumAdBlockRuleCompiler {
    /// Guard against pathological list growth: per-request matching walks
    /// suffix buckets + an Aho-Corasick scan, so bound the scoped set.
    static let maxScopedRules = 150_000

    /// Shared curated list; the canonical text lives on ContentBlocker so
    /// both engines consume it.
    static var youtubeFilterText: String { ContentBlocker.curatedYouTubeFilters }

    static func compile(_ texts: [String]) -> ChromiumAdBlockRules {
        var blockedDomains = Set<String>()
        var allowedDomains = Set<String>()
        var blockedPatterns = Set<String>()
        var allowedPatterns = Set<String>()
        var globalSelectors = Set<String>()
        var domainSelectors: [String: Set<String>] = [:]
        var cosmeticExceptions: [String: Set<String>] = [:]
        var networkRules: [ChromiumNetworkRule] = []

        for text in texts {
            text.enumerateLines { line, _ in
                parse(
                    line,
                    blockedDomains: &blockedDomains,
                    allowedDomains: &allowedDomains,
                    blockedPatterns: &blockedPatterns,
                    allowedPatterns: &allowedPatterns,
                    globalSelectors: &globalSelectors,
                    domainSelectors: &domainSelectors,
                    cosmeticExceptions: &cosmeticExceptions,
                    networkRules: &networkRules
                )
            }
        }

        blockedDomains.subtract(allowedDomains)
        blockedPatterns.subtract(allowedPatterns)
        // Scoped cosmetic exceptions only unhide their own domain: a
        // `example.com#@#.ad` exception must not remove `.ad` everywhere.
        // Global exceptions ("" key) apply to all scopes.
        let globalExceptions = cosmeticExceptions[""] ?? []
        globalSelectors.subtract(globalExceptions)
        for domain in domainSelectors.keys {
            domainSelectors[domain]?.subtract(globalExceptions)
            if let scoped = cosmeticExceptions[domain] {
                domainSelectors[domain]?.subtract(scoped)
            }
        }
        // Global selectors also lose domain-scoped exceptions? No — a scoped
        // exception only affects its domain's bucket, never the global set.

        return ChromiumAdBlockRules(
            blockedDomains: blockedDomains.sorted(),
            allowedDomains: allowedDomains.sorted(),
            blockedPatterns: blockedPatterns.sorted(),
            allowedPatterns: allowedPatterns.sorted(),
            globalSelectors: globalSelectors.sorted(),
            domainSelectors: domainSelectors
                .filter { !$0.value.isEmpty }
                .mapValues { $0.sorted() },
            networkRules: networkRules
        )
    }

    private static func parse(
        _ line: String,
        blockedDomains: inout Set<String>,
        allowedDomains: inout Set<String>,
        blockedPatterns: inout Set<String>,
        allowedPatterns: inout Set<String>,
        globalSelectors: inout Set<String>,
        domainSelectors: inout [String: Set<String>],
        cosmeticExceptions: inout [String: Set<String>],
        networkRules: inout [ChromiumNetworkRule]
    ) {
        let rule = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty, !rule.hasPrefix("!"), !rule.hasPrefix("[") else { return }

        if parseHostsRule(rule, into: &blockedDomains) { return }
        if parseCosmeticRule(
            rule,
            globalSelectors: &globalSelectors,
            domainSelectors: &domainSelectors,
            exceptions: &cosmeticExceptions
        ) { return }

        parseNetworkRule(
            rule,
            blockedDomains: &blockedDomains,
            allowedDomains: &allowedDomains,
            blockedPatterns: &blockedPatterns,
            allowedPatterns: &allowedPatterns,
            networkRules: &networkRules
        )
    }

    // MARK: - Network rules

    /// Canonical ABP content kinds. Negated kinds (`~script`) cannot be
    /// expressed (matchers are allowlists), so such rules are dropped.
    private static let contentKinds: Set<String> = [
        "script", "stylesheet", "image", "font", "media", "object", "other",
        "xhr", "websocket", "ping", "subdocument", "document",
    ]

    /// Options that only affect cosmetic/scriptlet handling: irrelevant to
    /// network matching, so ignored when network meaning exists elsewhere.
    private static let cosmeticOnlyOptions: Set<String> = [
        "elemhide", "generichide", "genericblock", "specifichide",
        "jsinject", "inline-script", "inline-font", "css",
    ]

    /// Options with no native representation: the rule is dropped rather
    /// than broadened.
    private static let unsupportedOptions: Set<String> = [
        "badfilter", "csp", "cookie", "header", "removeheader", "permissions",
        "referrerpolicy", "proxy", "method", "ipaddress", "jsonprune", "hls",
        "networkredirect", "urlskip", "replace", "denyallow", "urlblock",
    ]

    /// Options accepted and ignored: they don't narrow matching in ways the
    /// native matcher must enforce.
    private static let harmlessOptions: Set<String> = [
        "important", "empty", "mp4", "match-case",
    ]

    private static func parseNetworkRule(
        _ rule: String,
        blockedDomains: inout Set<String>,
        allowedDomains: inout Set<String>,
        blockedPatterns: inout Set<String>,
        allowedPatterns: inout Set<String>,
        networkRules: inout [ChromiumNetworkRule]
    ) {
        var networkRule = rule
        let isException = networkRule.hasPrefix("@@")
        if isException { networkRule.removeFirst(2) }
        let parts = networkRule.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        let pattern = String(parts[0])
        let rawOptions = parts.count == 2 ? String(parts[1]) : ""

        // Legacy fast path (bare `||domain^`, plain substrings).
        // Cosmetic-only exceptions (`@@…$elemhide` and friends) must never
        // become network allows: the native subset can't scope them, so
        // honoring them would disable network blocking site-wide. This is
        // also why `ublock-unbreak` stays out of the Chromium input.
        let optionTokens = rawOptions.isEmpty ? [] : rawOptions.split(separator: ",").map { $0.lowercased() }
        var important = false
        var scopedOptionCount = 0
        for token in optionTokens {
            let name = String(token.split(separator: "=", maxSplits: 1)[0])
            if name == "important" {
                important = true
            } else if !harmlessOptions.contains(name) && !cosmeticOnlyOptions.contains(name) {
                scopedOptionCount += 1
            }
        }
        let hasNetworkMeaning = scopedOptionCount > 0 || important
        if isException, !hasNetworkMeaning, !rawOptions.isEmpty {
            return
        }
        if !hasNetworkMeaning, let domain = domainAnchor(from: pattern) {
            if isException {
                allowedDomains.insert(domain)
            } else {
                blockedDomains.insert(domain)
            }
            return
        }
        if !hasNetworkMeaning {
            guard let substring = plainSubstring(from: pattern) else { return }
            if isException {
                allowedPatterns.insert(substring)
            } else {
                blockedPatterns.insert(substring)
            }
            return
        }

        guard networkRules.count < maxScopedRules,
              let scoped = scopedNetworkRule(
                  pattern: pattern,
                  options: optionTokens,
                  isException: isException,
                  important: important
              )
        else { return }
        networkRules.append(scoped)
    }

    /// Builds a scoped rule from an ABP pattern + option list.
    /// Returns nil when the rule cannot be represented faithfully.
    private static func scopedNetworkRule(
        pattern: String,
        options: [String],
        isException: Bool,
        important: Bool
    ) -> ChromiumNetworkRule? {
        var firstPartyVote = false
        var thirdPartyVote = false
        var domains: [String] = []
        var notDomains: [String] = []
        var types: [String] = []
        var popupOnly = false
        var excludePopup = false

        for token in options {
            let pieces = token.split(separator: "=", maxSplits: 1).map(String.init)
            let name = pieces[0]
            let value = pieces.count == 2 ? pieces[1] : nil

            switch name {
            case "third-party", "3p", "~first-party", "~1p", "strict3p":
                thirdPartyVote = true
            case "first-party", "1p", "~third-party", "~3p", "strict1p":
                firstPartyVote = true
            case "popup":
                popupOnly = true
            case "~popup":
                excludePopup = true
            case "important", "empty", "mp4", "match-case":
                break
            case "domain", "from", "to":
                guard let value else { return nil }
                for entry in value.split(separator: "|").map(String.init) {
                    if entry.hasPrefix("~") {
                        guard let domain = normalizedDomain(String(entry.dropFirst())) else { return nil }
                        notDomains.append(domain)
                    } else {
                        guard let domain = normalizedDomain(entry) else { return nil }
                        domains.append(domain)
                    }
                }
            case "css", "stylesheet", "style":
                types.append("stylesheet")
            case "xmlhttprequest":
                types.append("xhr")
            case "beacon":
                types.append("ping")
            case "frame":
                types.append("subdocument")
            default:
                if contentKinds.contains(name) {
                    types.append(name)
                } else if cosmeticOnlyOptions.contains(name) {
                    break
                } else if harmlessOptions.contains(name) {
                    break
                } else if unsupportedOptions.contains(name)
                    || name.hasPrefix("redirect") || name.hasPrefix("removeparam")
                    || name.hasPrefix("uritransform") || name.hasPrefix("prevent-") {
                    return nil
                } else if name.hasPrefix("~") {
                    // Negated resource kinds and unknown negations can't be mapped.
                    return nil
                } else {
                    return nil
                }
            }
        }

        // `first-party,third-party` together constrain nothing; the doubly
        // negated pair is pathological — treat the pair as unconstrained.
        let thirdParty: Int
        if firstPartyVote, thirdPartyVote {
            thirdParty = -1
        } else if thirdPartyVote {
            thirdParty = 1
        } else if firstPartyVote {
            thirdParty = 0
        } else {
            thirdParty = -1
        }

        let kind: ChromiumNetworkRule.Kind
        let value: String
        if let domain = domainAnchor(from: pattern) {
            kind = .domain
            value = domain
        } else if let substring = plainSubstring(from: pattern) {
            kind = .pattern
            value = substring
        } else {
            return nil
        }

        return ChromiumNetworkRule(
            value: value,
            kind: kind,
            exception: isException,
            thirdParty: thirdParty,
            domains: Array(Set(domains)).sorted(),
            notDomains: Array(Set(notDomains)).sorted(),
            types: Array(Set(types)).sorted(),
            important: important,
            popupOnly: popupOnly,
            excludePopup: excludePopup
        )
    }

    private static func parseHostsRule(_ rule: String, into domains: inout Set<String>) -> Bool {
        let parts = rule.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 2,
              ["0.0.0.0", "127.0.0.1", "::", "::1"].contains(String(parts[0]))
        else { return false }
        if let domain = normalizedDomain(String(parts[1])) {
            domains.insert(domain)
        }
        return true
    }

    private static func parseCosmeticRule(
        _ rule: String,
        globalSelectors: inout Set<String>,
        domainSelectors: inout [String: Set<String>],
        exceptions: inout [String: Set<String>]
    ) -> Bool {
        let marker: String
        let isException: Bool
        if rule.contains("#@#") {
            marker = "#@#"
            isException = true
        } else if rule.contains("##") {
            marker = "##"
            isException = false
        } else {
            return rule.contains("#")
        }

        guard let range = rule.range(of: marker) else { return true }
        let domainPart = String(rule[..<range.lowerBound])
        let selector = String(rule[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard isSafeSelector(selector) else { return true }

        if domainPart.isEmpty {
            if isException {
                exceptions["", default: []].insert(selector)
            } else {
                globalSelectors.insert(selector)
            }
            return true
        }

        let domains = domainPart.split(separator: ",").map(String.init)
        guard !domains.contains(where: { $0.hasPrefix("~") }) else { return true }
        for rawDomain in domains {
            guard let domain = normalizedDomain(rawDomain) else { continue }
            if isException {
                exceptions[domain, default: []].insert(selector)
            } else {
                domainSelectors[domain, default: []].insert(selector)
            }
        }
        return true
    }

    private static func domainAnchor(from pattern: String) -> String? {
        guard pattern.hasPrefix("||") else { return nil }
        let remainder = pattern.dropFirst(2)
        let end = remainder.firstIndex(where: { "^/*|?".contains($0) }) ?? remainder.endIndex
        guard end == remainder.endIndex || remainder[end] == "^" else { return nil }
        return normalizedDomain(String(remainder[..<end]))
    }

    private static func plainSubstring(from pattern: String) -> String? {
        // Anchor semantics must survive: a `||host/path` domain anchor keeps
        // its meaning as a host+path substring, but single leading/trailing
        // `|` pins (start/end/exact match) would be lost by stripping — an
        // unpinned `|ads` would block any URL merely containing "ads".
        // Skip those instead of broadening them.
        var candidate = pattern
        if candidate.hasPrefix("||") {
            candidate.removeFirst(2)
        } else if candidate.hasPrefix("|") || candidate.hasSuffix("|") {
            return nil
        }
        guard !candidate.contains("^"),
              !candidate.contains("*"),
              !candidate.contains("|"),
              candidate.count >= 6,
              !candidate.contains(" "),
              !candidate.hasPrefix("/")
        else { return nil }
        return candidate.lowercased()
    }

    private static func normalizedDomain(_ value: String) -> String? {
        let domain = value.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard domain.contains("."),
              !domain.contains(where: { $0.isWhitespace || "/*^|?=".contains($0) }),
              domain.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-"
              })
        else { return nil }
        return domain
    }

    private static func isSafeSelector(_ selector: String) -> Bool {
        !selector.isEmpty
            && selector.count <= 2_048
            && !selector.hasPrefix("+")
            && !selector.hasPrefix("^")
            && !selector.contains("##")
            && !selector.contains("{")
            && !selector.contains("}")
            && !selector.contains("\n")
            && !selector.contains("\u{2028}")
            && !selector.contains("\u{2029}")
            && !selector.contains(":has-text(")
            && !selector.contains(":matches-css(")
            && !selector.contains(":xpath(")
    }
}
