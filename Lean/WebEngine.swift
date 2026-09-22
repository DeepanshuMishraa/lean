import Foundation
import WebKit

/// Small, testable engine glue for the WKWebView-backed browser.
///
/// The Lean shell (LeanView / TopBar / Omnibar / Sidebar / Settings) never
/// touches WebKit directly — it talks to `LeanTab`. This file holds the only
/// policy decisions the engine needs, kept pure so they are unit-testable
/// without a running web view. UI presentation (sheets, alerts, workspace
/// opens) lives in `LeanTab`.
enum ExternalLinkPolicy {
    /// Schemes that must always render inside the web view.
    private static let inWebViewSchemes: Set<String> = [
        "http", "https", "file", "lean", "about", "data", "blob", "javascript"
    ]

    /// True when the URL should be handed to `NSWorkspace` instead of the
    /// web view (mailto:, tel:, sms:, app schemes like slack://, OAuth
    /// callbacks like myapp://, …).
    static func shouldOpenExternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return false }
        if inWebViewSchemes.contains(scheme) { return false }
        return true
    }
}

enum DownloadPolicy {
    /// True when a navigation response must become a `WKDownload` instead of
    /// rendering inline. Previously only `Content-Disposition: attachment`
    /// triggered this, so octet-streams and some bank/SSO exports rendered
    /// blank. Inline HTML/images/PDFs still render.
    static func shouldDownload(
        contentDisposition: String?,
        mimeType: String?
    ) -> Bool {
        if let disposition = contentDisposition?.lowercased() {
            // Parse the disposition *type* (before ';') so an inline
            // filename containing "attachment" doesn't trigger a download.
            let dispositionType = disposition.split(separator: ";", maxSplits: 1)
                .first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if dispositionType == "attachment" {
                return true
            }
        }
        if let mime = mimeType?.lowercased().trimmingCharacters(in: .whitespaces),
           mime == "application/octet-stream" {
            return true
        }
        return false
    }
}

@MainActor
final class MediaPermissionStore: ObservableObject {
    private var decisions: [String: Bool] = [:]
    private let database: AppDatabase?
    private static let storageKey = "mediaCapturePermissions_v1"

    init(database: AppDatabase? = nil) {
        self.database = database
        if let database {
            switch database.value([String: Bool].self, forKey: Self.storageKey) {
            case .success(let saved):
                decisions = saved ?? [:]
            case .failure(let error):
                NSLog("Could not read media permissions: %@", String(describing: error))
            }
        }
    }

    /// Canonical per-origin key: `scheme://host[:port]`, omitting default
    /// ports so `https://example.com` and `https://example.com:443` share
    /// one permission entry. Pure — no isolation.
    nonisolated static func originKey(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if let port = url.port,
           !((scheme == "http" && port == 80) || (scheme == "https" && port == 443)) {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    func decision(forOriginKey origin: String) -> Bool? {
        decisions[origin]
    }

    func setDecision(_ allowed: Bool, forOriginKey origin: String) {
        decisions[origin] = allowed
        persist()
    }

    func clear() {
        decisions.removeAll()
        persist()
    }

    private func persist() {
        guard let database else { return }
        if case .failure(let error) = database.set(decisions, forKey: Self.storageKey) {
            NSLog("Could not persist media permissions: %@", String(describing: error))
        }
    }
}
