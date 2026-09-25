import Foundation
import Testing
@testable import Lean

struct ExternalLinkPolicyTests {
    @Test("Web URLs stay in the web view")
    func webURLsStay() {
        #expect(!ExternalLinkPolicy.shouldOpenExternally(URL(string: "https://example.com")!))
        #expect(!ExternalLinkPolicy.shouldOpenExternally(URL(string: "http://example.com")!))
        #expect(!ExternalLinkPolicy.shouldOpenExternally(URL(string: "lean://settings")!))
    }

    @Test("Mail, tel, and app schemes open externally")
    func externalSchemes() {
        #expect(ExternalLinkPolicy.shouldOpenExternally(URL(string: "mailto:a@b.com")!))
        #expect(ExternalLinkPolicy.shouldOpenExternally(URL(string: "tel:+123456789")!))
        #expect(ExternalLinkPolicy.shouldOpenExternally(URL(string: "slack://open")!))
        #expect(ExternalLinkPolicy.shouldOpenExternally(URL(string: "zoommtg://zoom.us/join?confno=1")!))
        #expect(ExternalLinkPolicy.shouldOpenExternally(URL(string: "myapp://oauth/callback?code=1")!))
    }
}

struct SiteBlockingPolicyTests {
    @Test("Site exceptions apply only to the exact host")
    func exactHostExceptions() {
        let exceptions: Set<String> = ["example.com"]
        #expect(!SiteBlockingPolicy.shouldBlock(globalEnabled: true, host: "example.com", excludedHosts: exceptions))
        #expect(SiteBlockingPolicy.shouldBlock(globalEnabled: true, host: "shop.example.com", excludedHosts: exceptions))
        #expect(!SiteBlockingPolicy.shouldBlock(globalEnabled: true, host: "EXAMPLE.COM.", excludedHosts: exceptions))
        #expect(!SiteBlockingPolicy.shouldBlock(globalEnabled: false, host: "other.example", excludedHosts: []))
    }
}

struct DownloadPolicyTests {
    @Test("Attachment disposition becomes a download")
    func attachment() {
        #expect(DownloadPolicy.shouldDownload(
            contentDisposition: "attachment; filename=\"a.pdf\"",
            mimeType: "application/pdf"
        ))
    }

    @Test("Octet-stream becomes a download even without attachment")
    func octetStream() {
        #expect(DownloadPolicy.shouldDownload(
            contentDisposition: nil,
            mimeType: "application/octet-stream"
        ))
    }

    @Test("Inline pages still render")
    func inline() {
        #expect(!DownloadPolicy.shouldDownload(contentDisposition: nil, mimeType: "text/html"))
        #expect(!DownloadPolicy.shouldDownload(contentDisposition: "inline", mimeType: "application/pdf"))
        #expect(!DownloadPolicy.shouldDownload(contentDisposition: "inline; filename=\"attachment.pdf\"", mimeType: "application/pdf"))
        #expect(!DownloadPolicy.shouldDownload(contentDisposition: nil, mimeType: nil))
    }

    @Test("Unshowable MIME types become downloads")
    func unshowableMimeType() {
        #expect(DownloadPolicy.shouldDownload(
            contentDisposition: nil,
            mimeType: "application/zip",
            canShowMIMEType: false
        ))
        #expect(!DownloadPolicy.shouldDownload(
            contentDisposition: nil,
            mimeType: "text/html",
            canShowMIMEType: true
        ))
    }
}

struct MediaPermissionStoreTests {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "lean.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test("Origin keys are scheme + host scoped")
    func originKeys() {
        #expect(MediaPermissionStore.originKey(for: URL(string: "https://meet.google.com/x")!) == "https://meet.google.com")
        #expect(MediaPermissionStore.originKey(for: URL(string: "https://meet.google.com:443")!) == "https://meet.google.com")
        #expect(MediaPermissionStore.originKey(for: URL(string: "http://localhost:80")!) == "http://localhost")
        #expect(MediaPermissionStore.originKey(for: URL(string: "http://localhost:3000/")!) == "http://localhost:3000")
        #expect(MediaPermissionStore.originKey(for: URL(string: "about:blank")!) == nil)
    }

    @MainActor
    @Test("Decisions round-trip in memory without a database")
    func inMemoryDecisions() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MediaPermissionStore(database: nil, userDefaults: defaults)
        #expect(store.decision(forOriginKey: "https://meet.google.com|microphone") == nil)
        store.setDecision(true, forOriginKey: "https://meet.google.com|microphone")
        #expect(store.decision(forOriginKey: "https://meet.google.com|microphone") == true)
        store.setDecision(false, forOriginKey: "https://meet.google.com|camera")
        #expect(store.decision(forOriginKey: "https://meet.google.com|camera") == false)
        store.setDecision(true, forOriginKey: "https://other.example|microphone")
        #expect(store.savedDecisions.count == 3)
        store.clear(origin: "https://meet.google.com")
        #expect(store.savedDecisions.map(\.origin) == ["https://other.example"])
        store.clear()
        #expect(store.decision(forOriginKey: "https://meet.google.com|microphone") == nil)
    }

    @MainActor
    @Test("Decisions survive without a database via the defaults mirror")
    func defaultsMirrorWithoutDatabase() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = MediaPermissionStore(database: nil, userDefaults: defaults)
        first.setDecision(true, forOriginKey: "https://meet.google.com|microphone")
        // A fresh instance with no database — a launch where sqlite is
        // unavailable — still sees yesterday's answer instead of asking again.
        let second = MediaPermissionStore(database: nil, userDefaults: defaults)
        #expect(second.decision(forOriginKey: "https://meet.google.com|microphone") == true)
        #expect(second.decision(forOriginKey: "https://meet.google.com|camera") == nil)
    }

    @MainActor
    @Test("An explicitly cleared database is not resurrected by the mirror")
    func explicitEmptyBeatsMirror() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Lean.sqlite3")

        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let database = try AppDatabase(url: url)
        let first = MediaPermissionStore(database: database, userDefaults: defaults)
        first.setDecision(true, forOriginKey: "https://meet.google.com|microphone")
        first.clear()
        // Database now holds an explicit empty dictionary. Plant a stale
        // mirror entry directly (same key MediaPermissionStore persists
        // under): a fresh instance must stay empty, not resurrect it.
        defaults.set(
            ["https://meet.google.com|microphone": true],
            forKey: "mediaCapturePermissions_v1"
        )
        let second = MediaPermissionStore(database: try AppDatabase(url: url), userDefaults: defaults)
        #expect(second.savedDecisions.isEmpty)
        #expect(second.decision(forOriginKey: "https://meet.google.com|microphone") == nil)
    }

    @MainActor
    @Test("Decisions survive a database reopen")
    func databaseRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Lean.sqlite3")

        let (firstDefaults, firstSuite) = isolatedDefaults()
        defer { firstDefaults.removePersistentDomain(forName: firstSuite) }
        let first = MediaPermissionStore(database: try AppDatabase(url: url), userDefaults: firstDefaults)
        first.setDecision(false, forOriginKey: "https://example.com|camera")

        // A clean defaults suite proves the database (not the mirror)
        // carried the decision across.
        let (secondDefaults, secondSuite) = isolatedDefaults()
        defer { secondDefaults.removePersistentDomain(forName: secondSuite) }
        let second = MediaPermissionStore(database: try AppDatabase(url: url), userDefaults: secondDefaults)
        #expect(second.decision(forOriginKey: "https://example.com|camera") == false)
    }
}
