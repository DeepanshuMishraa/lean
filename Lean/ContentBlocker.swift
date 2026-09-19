import WebKit

@MainActor
enum ContentBlocker {
    private static let identifier = "BuiltInBlocker"

    private static let rules = #"""
    [
      {
        "trigger": {
          "url-filter": ".*",
          "if-domain": [
            "*2mdn.net", "*adnxs.com", "*adsrvr.org", "*amazon-adsystem.com",
            "*criteo.com", "*criteo.net", "*doubleclick.net", "*googlesyndication.com",
            "*googleadservices.com", "*scorecardresearch.com", "*taboola.com",
            "*outbrain.com", "*quantserve.com"
          ]
        },
        "action": { "type": "block" }
      },
      {
        "trigger": {
          "url-filter": ".*",
          "if-domain": [
            "*google-analytics.com", "*googletagmanager.com", "*segment.io",
            "*segment.com", "*mixpanel.com", "*hotjar.com", "*fullstory.com"
          ]
        },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": ".*" },
        "action": {
          "type": "css-display-none",
          "selector": ".adsbygoogle, [id^='google_ads_'], [class*='ad-container'], [data-ad-slot]"
        }
      }
    ]
    """#

    static func ruleList() async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        if let cached = try? await store.contentRuleList(forIdentifier: identifier) {
            return cached
        }

        return try? await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: rules
            ) { ruleList, error in
                if let ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: error ?? ContentBlockerError.compilationFailed)
                }
            }
        }
    }
}

private enum ContentBlockerError: Error {
    case compilationFailed
}
