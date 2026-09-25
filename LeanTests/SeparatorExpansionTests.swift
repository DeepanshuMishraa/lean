import Foundation
import Testing
import WebKit
@testable import Lean

/// WebKit's url-filter dialect rejects `|` outright, so the `^`
/// separator-or-end marker must expand into alternation-free rules.
/// A single invalid rule rejects its whole 40k list — which is how one
/// bad pattern stranded refreshes and sprayed orphan files per launch.
struct SeparatorExpansionTests {
    private func filters(in result: AdBlockFilterConverter.ConversionResult) -> [String] {
        result.rules.compactMap { ($0["trigger"] as? [String: Any])?["url-filter"] as? String }
    }

    @Test("Trailing separator expands to class and anchor variants")
    func trailingSeparator() {
        let result = AdBlockFilterConverter.convert("||ads.example^")
        let found = filters(in: result)
        #expect(found.count == 2)
        #expect(found.allSatisfy { !$0.contains("|") && !$0.contains("(?:") })
        #expect(found.contains { $0.hasSuffix("$") })
        #expect(found.contains { $0.hasSuffix("[^a-zA-Z0-9_\\-.%]") })
    }

    @Test("Mid-pattern separator stays a single class rule")
    func midSeparator() {
        let result = AdBlockFilterConverter.convert("||ads.example^/banner")
        let found = filters(in: result)
        #expect(found.count == 1)
        #expect(found[0].contains("[^a-zA-Z0-9_\\-.%]/banner"))
    }

    @Test("Literal pipes are skipped, not mistranslated")
    func interiorPipeSkipped() {
        let result = AdBlockFilterConverter.convert("||ads.example/a|b")
        #expect(result.rules.isEmpty)
    }

    @Test("Separator expansion compiles in WebKit")
    func compiles() async throws {
        let result = AdBlockFilterConverter.convert("||ads.example^/banner^")
        #expect(result.rules.count == 2)
        guard let data = try? JSONSerialization.data(withJSONObject: result.rules),
              let json = String(data: data, encoding: .utf8),
              let store = WKContentRuleListStore.default() else {
            Issue.record("setup failed")
            return
        }
        do {
            let _: WKContentRuleList = try await withCheckedThrowingContinuation { c in
                store.compileContentRuleList(forIdentifier: "lean-separator-probe", encodedContentRuleList: json) { l, e in
                    if let l { c.resume(returning: l) } else { c.resume(throwing: e ?? NSError(domain: "probe", code: 1)) }
                }
            }
        } catch {
            Issue.record("separator rules rejected: \(error)")
        }
        try? await store.removeContentRuleList(forIdentifier: "lean-separator-probe")
    }
}
