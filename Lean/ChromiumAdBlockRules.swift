import Foundation

struct ChromiumAdBlockRules: Sendable {
    var blockedDomains: [String]
    var allowedDomains: [String]
    var blockedPatterns: [String]
    var allowedPatterns: [String]
    var globalSelectors: [String]
    var domainSelectors: [String: [String]]
}

enum ChromiumAdBlockRuleCompiler {
    static func compile(_ texts: [String]) -> ChromiumAdBlockRules {
        var blockedDomains = Set<String>()
        var allowedDomains = Set<String>()
        var blockedPatterns = Set<String>()
        var allowedPatterns = Set<String>()
        var globalSelectors = Set<String>()
        var domainSelectors: [String: Set<String>] = [:]
        var cosmeticExceptions: [String: Set<String>] = [:]

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
                    cosmeticExceptions: &cosmeticExceptions
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
                .mapValues { $0.sorted() }
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
        cosmeticExceptions: inout [String: Set<String>]
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

        var networkRule = rule
        let isException = networkRule.hasPrefix("@@")
        if isException { networkRule.removeFirst(2) }
        let parts = networkRule.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        let pattern = String(parts[0])
        let options = parts.count == 2 ? String(parts[1]) : ""
        guard !options.split(separator: ",").contains(where: {
            let option = $0.lowercased()
            return option == "badfilter" || option.hasPrefix("redirect") || option.hasPrefix("removeparam")
        }) else { return }

        if let domain = domainAnchor(from: pattern) {
            if isException {
                // Cosmetic-only exceptions (elemhide/generichide/...) must not
                // disable network blocking: this native subset can't scope
                // them, so ignoring them here keeps network protection while
                // cosmetic handling lives in the stylesheet path.
                let optionList = options.split(separator: ",").map { $0.lowercased() }
                let cosmeticOnly: Set<String> = [
                    "elemhide", "generichide", "genericblock", "specifichide",
                    "jsinject", "inline-script", "inline-font", "css",
                ]
                if !options.isEmpty, optionList.allSatisfy({ cosmeticOnly.contains(String($0)) }) {
                    return
                }
                // Broadly honoring scoped exceptions is safer than breaking a
                // site when this native subset cannot represent every option.
                allowedDomains.insert(domain)
            } else if options.isEmpty || options == "important" {
                blockedDomains.insert(domain)
            }
            return
        }

        guard options.isEmpty, let substring = plainSubstring(from: pattern) else { return }
        if isException {
            allowedPatterns.insert(substring)
        } else {
            blockedPatterns.insert(substring)
        }
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
        // Never strip anchor semantics: `|`, `||`, `^`, and path separators
        // carry host/position meaning. Stripping them turns an anchored or
        // path-scoped filter into an unrestricted substring that blocks
        // unrelated URLs — skip these patterns instead.
        guard !pattern.contains("|"),
              !pattern.contains("^"),
              !pattern.contains("*"),
              !pattern.contains("/")
        else { return nil }
        var candidate = pattern
        guard candidate.count >= 6,
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
