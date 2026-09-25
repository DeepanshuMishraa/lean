import Foundation

/// Converts AdBlock Plus / uBlock Origin filter lists into WebKit content-blocker JSON rules.
///
/// Supported input is the subset of ABP/uBO syntax that maps faithfully onto
/// `WKContentRuleList` triggers:
/// - network filters (`||domain^`, `|anchor`, plain substrings, `@@` exceptions)
///   with `third-party`, `domain=`/`from=`, and resource-type options
/// - plain cosmetic filters (`domain##selector`)
/// - `/etc/hosts`-style lines (Peter Lowe's list)
///
/// Anything that cannot be represented faithfully (scriptlets, procedural
/// cosmetics, redirects, CSP, `removeparam`, mixed include/exclude domains,
/// regex filters, ...) is skipped rather than broadened.
enum AdBlockFilterConverter {
    static let maxRulesPerList = 40_000
    /// 8 lists × 40k: the most WebKit will attach. Trailing `^` expands one
    /// filter line into two rules, so the cap must cover the expansion.
    static let maxTotalRules = 320_000

    struct ConversionResult {
        var rules: [[String: Any]]
        var keptCount: Int
        var skippedCount: Int
    }

    /// Convert raw filter-list text into WebKit content-blocker rule dictionaries.
    static func convert(_ text: String) -> ConversionResult {
        var rules: [[String: Any]] = []
        var seen = Set<String>()
        var skipped = 0

        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let converted = convertLine(trimmed)
            guard !converted.isEmpty else {
                skipped += 1
                return
            }
            for rule in converted {
                let key = canonicalKey(for: rule)
                guard seen.insert(key).inserted else {
                    skipped += 1
                    continue
                }
                rules.append(rule)
                if rules.count >= maxTotalRules {
                    // Keep counting the rest as skipped without building more rules.
                    skipped += 1
                }
            }
        }

        return ConversionResult(rules: rules, keptCount: rules.count, skippedCount: skipped)
    }

    /// Split converted rules into per-list chunks that stay under WebKit's rule limit.
    static func chunk(_ rules: [[String: Any]], maxRules: Int = maxRulesPerList) -> [[[String: Any]]] {
        guard maxRules > 0 else { return [] }
        var chunks: [[[String: Any]]] = []
        var current: [[String: Any]] = []
        current.reserveCapacity(min(maxRules, rules.count))
        for rule in rules {
            current.append(rule)
            if current.count >= maxRules {
                chunks.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    // MARK: - Line dispatch

    private static func convertLine(_ line: String) -> [[String: Any]] {
        if line.hasPrefix("!") || line.hasPrefix("[Adblock") {
            return []
        }
        if let hostsRule = convertHostsLine(line) {
            return [hostsRule]
        }
        // Cosmetic filters contain ## / #@# / #?# markers.
        if line.contains("#") {
            if let rule = convertCosmetic(line) {
                return [rule]
            }
            return []
        }
        return convertNetwork(line)
    }

    /// `127.0.0.1 adserver.example` / `0.0.0.0 adserver.example`
    private static func convertHostsLine(_ line: String) -> [String: Any]? {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 2 else { return nil }
        let ip = parts[0]
        guard ip == "127.0.0.1" || ip == "0.0.0.0" || ip == "::1" || ip == "::" else { return nil }
        let host = String(parts[1]).lowercased()
        guard !host.isEmpty, host != "localhost", host != "localhost.localdomain",
              !host.hasPrefix("#"), host.contains("."), !host.contains("|") else { return nil }
        return [
            "trigger": ["url-filter": "^https?://([^/]*\\.)?" + escapeRegex(host)],
            "action": ["type": "block"]
        ]
    }

    // MARK: - Network filters

    private static func convertNetwork(_ line: String) -> [[String: Any]] {
        var pattern = line
        var isException = false
        if pattern.hasPrefix("@@") {
            isException = true
            pattern = String(pattern.dropFirst(2))
        }

        // Regex-style filters (/.../) have no faithful WebKit translation.
        if pattern.hasPrefix("/") && pattern.count > 2 {
            return []
        }

        let (barePattern, options) = splitOptions(pattern)
        // A `$...=...` suffix that didn't parse as an option list (e.g. a
        // `$csp=` value containing spaces) was meant as options — never treat
        // it as a URL pattern.
        if barePattern == pattern,
           let dollar = pattern.lastIndex(of: "$"),
           pattern[pattern.index(after: dollar)...].contains("=") {
            return []
        }
        pattern = barePattern
        guard !pattern.isEmpty else { return [] }
        // Network patterns never contain raw spaces or quotes.
        if pattern.contains(" ") || pattern.contains("'") || pattern.contains("\"") {
            return []
        }

        // Options that change semantics beyond what WebKit can express -> skip.
        // `important`, `match-case`, and `popup` are honoured; resource types,
        // third-party/first-party, and domain/from/to scoping are mapped.
        let unsupportedOptions: Set<String> = [
            "redirect", "redirect-rule", "replace", "csp", "removeparam", "queryprune",
            "removeheader", "header", "cookie", "permissions", "referrerpolicy",
            "urlskip", "urltransform", "uritransform", "uritransforms", "hls",
            "jsonprune", "networkredirect", "proxy", "method", "ipaddress",
            "strict1p", "strict3p", "denyallow", "urlblock", "genericblock",
            "generichide", "elemhide", "specifichide", "jsinject", "empty", "mp4",
            "inline-script", "inline-font"
        ]
        for option in options {
            let name = option.name
            if unsupportedOptions.contains(name) {
                return []
            }
            if name.hasPrefix("redirect") || name.hasPrefix("prevent-") || name.hasPrefix("uritransform") {
                return []
            }
        }

        // `badfilter` negates another rule; without that pairing info, drop it.
        if options.contains(where: { $0.name == "badfilter" }) {
            return []
        }
        // `$popup` alone blocks popups; combined with resource types WebKit can't scope. Keep simple case.
        let hasPopup = options.contains(where: { $0.name == "popup" || $0.name == "~popup" })

        var resourceTypes: [String] = []
        var loadType: [String]? = nil
        var ifDomain: [String]? = nil
        var unlessDomain: [String]? = nil
        var matchCase = false
        var hasThirdPartyOption = false

        var includeDomains: [String] = []
        var excludeDomains: [String] = []

        for option in options {
            switch option.name {
            case "third-party", "3p":
                hasThirdPartyOption = true
                loadType = ["third-party"]
            case "~third-party", "~3p", "first-party", "1p":
                hasThirdPartyOption = true
                loadType = ["first-party"]
            case "~first-party", "~1p":
                // `~first-party` == third-party, but combined with an explicit
                // third-party option the meaning is muddled; keep it simple.
                if loadType == nil {
                    hasThirdPartyOption = true
                    loadType = ["third-party"]
                }
            case "match-case":
                matchCase = true
            case "popup":
                break
            case "script":
                resourceTypes.append("script")
            case "stylesheet", "css", "style":
                resourceTypes.append("style-sheet")
            case "image":
                resourceTypes.append("image")
            case "font":
                resourceTypes.append("font")
            case "media":
                resourceTypes.append("media")
            case "object", "other", "xmlhttprequest", "xhr", "websocket",
                 "ping", "beacon", "webrtc", "subdocument", "frame", "document":
                // WebKit has no dedicated frame/XHR/beacon types; `document`
                // covers subdocuments and `raw` covers the rest.
                if option.name == "subdocument" || option.name == "frame" || option.name == "document" {
                    if !resourceTypes.contains("document") { resourceTypes.append("document") }
                } else if !resourceTypes.contains("raw") {
                    resourceTypes.append("raw")
                }
            case "domain", "from", "to":
                let domains = option.value?.split(separator: "|").map(String.init) ?? []
                for domain in domains {
                    if domain.hasPrefix("~") {
                        let clean = String(domain.dropFirst())
                        guard isPlainDomain(clean) else { return [] }
                        excludeDomains.append(clean.lowercased())
                    } else {
                        guard isPlainDomain(domain) else { return [] }
                        includeDomains.append(domain.lowercased())
                    }
                }
            default:
                // Tilde-prefixed resource types are negations (e.g. `~script`).
                // WebKit triggers are allowlists, so negations can't be mapped.
                // Unknown positive options are only safe if they don't restrict
                // matching in ways we'd silently drop.
                if option.name.hasPrefix("~") {
                    return []
                }
                if isKnownHarmlessOption(option.name) {
                    continue
                }
                return []
            }
        }

        // WebKit triggers accept either if-domain or unless-domain, never both.
        if !includeDomains.isEmpty, !excludeDomains.isEmpty {
            return []
        }
        if !includeDomains.isEmpty {
            ifDomain = Array(Set(includeDomains)).sorted().map { "*\($0)" }
        } else if !excludeDomains.isEmpty {
            unlessDomain = Array(Set(excludeDomains)).sorted().map { "*\($0)" }
        }

        // `$popup` combined with resource scoping can't be expressed; keep the
        // common bare `||x^$popup` / `$third-party,popup` shape as a popup rule.
        if hasPopup, !resourceTypes.isEmpty {
            return []
        }

        guard let urlFilters = networkURLFilter(from: pattern) else { return [] }
        guard urlFilters.allSatisfy({ $0.count <= 1024 }) else { return [] }

        return urlFilters.map { urlFilter in
            var trigger: [String: Any] = ["url-filter": urlFilter]
            if matchCase {
                trigger["url-filter-is-case-sensitive"] = true
            }
            if let loadType {
                trigger["load-type"] = loadType
            }
            if let ifDomain {
                trigger["if-domain"] = ifDomain
            } else if let unlessDomain {
                trigger["unless-domain"] = unlessDomain
            }
            if hasPopup, resourceTypes.isEmpty {
                trigger["resource-type"] = ["popup"]
            } else if !resourceTypes.isEmpty {
                trigger["resource-type"] = Array(Set(resourceTypes)).sorted()
            }
            if isException {
                return ["trigger": trigger, "action": ["type": "ignore-previous-rules"]]
            }
            return ["trigger": trigger, "action": ["type": "block"]]
        }
    }

    private struct FilterOption {
        var name: String
        var value: String?
    }

    /// Split `pattern$options` on the last `$` when the suffix parses as an option list.
    private static func splitOptions(_ line: String) -> (String, [FilterOption]) {
        guard let dollarIndex = line.lastIndex(of: "$") else {
            return (line, [])
        }
        let suffix = String(line[line.index(after: dollarIndex)...])
        guard !suffix.isEmpty, !suffix.contains("/"), !suffix.contains(" "),
              !suffix.contains("^"), !suffix.contains("*") else {
            return (line, [])
        }
        let tokens = suffix.split(separator: ",").map(String.init)
        guard !tokens.isEmpty else { return (line, []) }
        var parsed: [FilterOption] = []
        for token in tokens {
            if token.isEmpty { return (line, []) }
            if let eq = token.firstIndex(of: "=") {
                let name = String(token[..<eq]).lowercased()
                let value = String(token[token.index(after: eq)...])
                guard !name.isEmpty, isOptionName(name) else { return (line, []) }
                parsed.append(FilterOption(name: name, value: value))
            } else {
                let name = token.lowercased()
                guard isOptionName(name) || name.hasPrefix("~") else { return (line, []) }
                let base = name.hasPrefix("~") ? String(name.dropFirst()) : name
                guard isOptionName(base) || isKnownHarmlessOption(base) else { return (line, []) }
                parsed.append(FilterOption(name: name, value: nil))
            }
        }
        // A suffix that parses as options but has no recognized option is
        // likely a literal `$` in the pattern (e.g. query strings).
        let recognized = parsed.contains { isOptionName($0.name) || $0.name == "popup" || $0.name == "~popup" }
        guard recognized else { return (line, []) }
        return (String(line[..<dollarIndex]), parsed)
    }

    private static func isOptionName(_ name: String) -> Bool {
        let base = name.hasPrefix("~") ? String(name.dropFirst()) : name
        return isKnownOption(base) || isKnownHarmlessOption(base)
    }

    private static func isKnownOption(_ name: String) -> Bool {
        switch name {
        case "script", "stylesheet", "css", "style", "image", "font", "media",
             "object", "other", "xmlhttprequest", "xhr", "websocket", "ping", "beacon",
             "webrtc", "subdocument", "frame", "document", "popup",
             "third-party", "3p", "first-party", "1p",
             "domain", "from", "to", "match-case", "important", "badfilter",
             "denyallow", "redirect", "redirect-rule", "replace", "csp", "removeparam",
             "queryprune", "removeheader", "header", "cookie", "permissions",
             "referrerpolicy", "urlskip", "urltransform", "uritransform", "hls",
             "jsonprune", "networkredirect", "proxy", "method", "ipaddress",
             "strict1p", "strict3p", "urlblock", "genericblock", "generichide",
             "elemhide", "specifichide", "jsinject", "empty", "mp4",
             "inline-script", "inline-font":
            return true
        default:
            if name.hasPrefix("redirect") || name.hasPrefix("prevent-") || name.hasPrefix("uritransform") {
                return true
            }
            return false
        }
    }

    private static func isKnownHarmlessOption(_ name: String) -> Bool {
        // Accepted and ignored: they don't narrow matching in ways WebKit must enforce.
        switch name {
        case "important", "empty", "mp4":
            return true
        default:
            return false
        }
    }

    private static func isPlainDomain(_ value: String) -> Bool {
        guard !value.isEmpty, !value.contains("*"), !value.contains("/"),
              !value.contains("^"), !value.contains("?"), !value.contains("#"),
              !value.contains(":") else { return false }
        // uBO entity syntax (`example.*`) and regex domains have no WebKit equivalent.
        if value.hasSuffix(".*") || value.contains(".*") { return false }
        if value.hasPrefix("/") || value.hasSuffix("/") { return false }
        let labels = value.split(separator: ".")
        guard labels.count >= 2 || value == "localhost" else { return false }
        for label in labels {
            if label.isEmpty || label.count > 63 { return false }
            if label.hasPrefix("-") || label.hasPrefix("~") { return false }
        }
        return true
    }

    /// Convert an ABP network pattern to WebKit `url-filter` regexes.
    /// One pattern can yield two filters (see `wildcardToRegex`).
    private static func networkURLFilter(from pattern: String) -> [String]? {
        var work = pattern
        var anchoredStart = false
        var anchoredEnd = false

        if work.hasPrefix("||") {
            work = String(work.dropFirst(2))
            // Domain-anchored: split host from the rest (`||host^path`).
            let separators = CharacterSet(charactersIn: "/^?#*")
            var hostEnd = work.endIndex
            for index in work.indices {
                let scalar = work[index].unicodeScalars.first
                if let scalar, separators.contains(scalar) {
                    hostEnd = index
                    break
                }
            }
            var host = String(work[..<hostEnd])
            let rest = String(work[hostEnd...])
            host = host.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            guard !host.isEmpty else { return nil }
            guard isPlainDomain(host.lowercased()) || host.lowercased().contains(".") else { return nil }
            let hostPart = "^https?://([^/]*\\.)?" + escapeRegex(host.lowercased())
            if rest.isEmpty {
                return [hostPart]
            }
            guard let rests = wildcardToRegex(rest) else { return nil }
            return rests.map { hostPart + $0 }
        }

        if work.hasPrefix("|") {
            anchoredStart = true
            work = String(work.dropFirst())
        }
        if work.hasSuffix("|") {
            anchoredEnd = true
            work = String(work.dropLast())
        }
        guard !work.isEmpty else { return nil }
        guard let bodies = wildcardToRegex(work) else { return nil }
        return bodies.map { body in
            var result = body
            if anchoredStart {
                result = "^" + result
            }
            if anchoredEnd {
                result += "$"
            }
            return result
        }
    }

    /// Separator-or-end without alternation: WebKit's url-filter dialect
    /// rejects `|` outright, so a trailing `^` expands to two variants —
    /// a separator class and an end anchor. A mid-pattern `^` can only be
    /// a separator. No groups are emitted.
    private static let separatorClass = "[^a-zA-Z0-9_\\-.%]"

    /// Translate `*` (any run) and `^` (separator-or-end) to regex, escaping
    /// the rest. Returns one filter, or two when the pattern ends in `^`.
    /// A literal `|` can be neither escaped (WebKit rejects `\|`) nor left
    /// raw (it would read as alternation): patterns containing one are
    /// skipped rather than mistranslated.
    private static func wildcardToRegex(_ pattern: String) -> [String]? {
        guard !pattern.contains("|") else { return nil }
        var outs = [""]
        let chars = Array(pattern)
        for (index, char) in chars.enumerated() {
            switch char {
            case "*":
                for i in outs.indices { outs[i] += ".*" }
            case "^":
                if index == chars.count - 1 {
                    let ended = outs.map { $0 + "$" }
                    for i in outs.indices { outs[i] += separatorClass }
                    outs += ended
                } else {
                    for i in outs.indices { outs[i] += separatorClass }
                }
            case ".", "?", "+", "[", "]", "(", ")", "{", "}", "$", "\\":
                for i in outs.indices { outs[i] += "\\" + String(char) }
            default:
                if char.isNewline { return nil }
                for i in outs.indices { outs[i].append(char) }
            }
        }
        return outs
    }

    private static func escapeRegex(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for char in value {
            switch char {
            case ".", "?", "+", "[", "]", "(", ")", "{", "}", "$", "^", "|", "\\", "*":
                out += "\\" + String(char)
            default:
                out.append(char)
            }
        }
        return out
    }

    // MARK: - Cosmetic filters

    private static func convertCosmetic(_ line: String) -> [String: Any]? {
        // Find the cosmetic marker. Order matters: `#@#` and `#?#` before `##`.
        let markers = ["#@#", "#$#", "#$$#", "#?#", "##"]
        var markerRange: Range<String.Index>? = nil
        var marker = ""
        for candidate in markers {
            if let range = line.range(of: candidate) {
                // Prefer the earliest marker; `##` inside a selector would be a false hit,
                // but ABP cosmetic markers always precede the selector, so earliest wins.
                if markerRange == nil || range.lowerBound < markerRange!.lowerBound {
                    markerRange = range
                    marker = candidate
                }
            }
        }
        guard let range = markerRange else { return nil }
        // Exceptions (`#@#`) and extended syntax can't map onto css-display-none safely.
        if marker == "#@#" || marker == "#$#" || marker == "#$$#" {
            return nil
        }

        let domainPart = String(line[..<range.lowerBound])
        let selector = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty, selector.count <= 1024 else { return nil }

        // Scriptlets, HTML filtering, and procedural operators have no WebKit equivalent.
        if selector.hasPrefix("+js(") || selector.hasPrefix("^") || selector.hasPrefix("{") {
            return nil
        }
        let unsupportedProcedural = [
            ":has-text(", ":contains(", ":xpath(", ":upward(", ":nth-ancestor(",
            ":-abp-", ":matches-css", ":matches-attr", ":matches-path",
            ":watch-attr", ":remove-attr", ":remove-class", ":remove(",
            ":style(", "+js(", "##^"
        ]
        for token in unsupportedProcedural where selector.contains(token) {
            return nil
        }
        // Bare `:has(` is standard CSS and WebKit-honoured; other procedural
        // forms above were already rejected.
        guard isPlausibleSelector(selector) else { return nil }

        var ifDomain: [String]? = nil
        var unlessDomain: [String]? = nil
        if !domainPart.isEmpty {
            // Element-hiding exceptions embedded in domain lists are out of scope.
            if domainPart.contains("~") && domainPart.contains(",") {
                var includes: [String] = []
                var excludes: [String] = []
                for piece in domainPart.split(separator: ",").map(String.init) {
                    let part = piece.trimmingCharacters(in: .whitespaces).lowercased()
                    if part.hasPrefix("~") {
                        let clean = String(part.dropFirst())
                        guard isPlainDomain(clean) else { return nil }
                        excludes.append(clean)
                    } else {
                        guard isPlainDomain(part) else { return nil }
                        includes.append(part)
                    }
                }
                // WebKit takes either if-domain or unless-domain, never both.
                if !includes.isEmpty, !excludes.isEmpty {
                    return nil
                }
                if !includes.isEmpty {
                    ifDomain = Array(Set(includes)).sorted().map { "*\($0)" }
                } else if !excludes.isEmpty {
                    unlessDomain = Array(Set(excludes)).sorted().map { "*\($0)" }
                }
            } else if domainPart.hasPrefix("~") {
                let clean = domainPart.lowercased().trimmingCharacters(in: .whitespaces).dropFirst()
                guard isPlainDomain(String(clean)) else { return nil }
                unlessDomain = ["*" + clean]
            } else {
                let clean = domainPart.lowercased().trimmingCharacters(in: .whitespaces)
                guard isPlainDomain(clean) else { return nil }
                ifDomain = ["*" + clean]
            }
        }

        var trigger: [String: Any] = ["url-filter": ".*"]
        if let ifDomain {
            trigger["if-domain"] = ifDomain
        } else if let unlessDomain {
            trigger["unless-domain"] = unlessDomain
        }
        return ["trigger": trigger, "action": ["type": "css-display-none", "selector": selector]]
    }

    private static func isPlausibleSelector(_ selector: String) -> Bool {
        if selector.contains("##") || selector.contains("@@") { return false }
        if selector.contains("{") || selector.contains("}") { return false }
        if selector.hasSuffix(",") { return false }
        // Reject obviously non-CSS payloads.
        if selector.contains("(") {
            let allowedFunctions = [":has(", ":is(", ":not(", ":where(", ":nth-child(", ":nth-of-type("]
            var scan = selector[...]
            while let open = scan.firstIndex(of: "(") {
                let before = String(scan[..<open])
                let isAllowed = allowedFunctions.contains { before.hasSuffix(String($0.dropLast())) }
                if !isAllowed {
                    // Plain attribute selectors like `[href="..."]` contain parens rarely;
                    // allow `[` contexts, reject the rest.
                    if !before.contains("[") {
                        return false
                    }
                }
                scan = scan[scan.index(after: open)...]
            }
        }
        return true
    }

    private static func canonicalKey(for rule: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: rule,
            options: [.sortedKeys]
        ) else {
            return UUID().uuidString
        }
        return String(decoding: data, as: UTF8.self)
    }
}
