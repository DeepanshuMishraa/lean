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
}

struct MediaPermissionStoreTests {
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
        let store = MediaPermissionStore(database: nil)
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
}
