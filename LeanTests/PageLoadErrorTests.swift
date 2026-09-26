import Foundation
import Testing
@testable import Lean

struct PageLoadErrorTests {
    /// A loopback port this test owns that refuses fast: bind an ephemeral
    /// port, listen, and close every accepted connection without answering.
    /// Merely holding a bound, non-listening socket hangs connects until
    /// timeout on macOS instead of refusing, so the accept loop is what
    /// makes the failure fast and deterministic. The caller closes `fd`
    /// after asserting.
    nonisolated static func refusedLoopbackServer() -> (port: UInt16, fd: Int32) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return (9, -1) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        guard withUnsafeMutablePointer(to: &addr, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }) == 0, listen(fd, 8) == 0 else { close(fd); return (9, -1) }
        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &len) }
        }
        let port = CFSwapInt16BigToHost(actual.sin_port)
        guard port != 0 else { close(fd); return (9, -1) }
        Thread.detachNewThread {
            while true {
                var client = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let cfd = withUnsafeMutablePointer(to: &client) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(fd, $0, &clientLen) }
                }
                if cfd < 0 { return }
                close(cfd)
            }
        }
        return (port, fd)
    }

    private func failure(code: Int, url: String = "http://localhost:3000/") -> (Error, URL) {
        let target = URL(string: url)!
        let error = NSError(domain: NSURLErrorDomain, code: code, userInfo: [NSURLErrorFailingURLErrorKey: target])
        return (error, target)
    }

    @Test("Cancellations and policy interruptions stay silent")
    func silentFailures() {
        let (cancelled, url) = failure(code: NSURLErrorCancelled)
        #expect(PageLoadError.from(cancelled, for: url) == nil)
        let interrupted = NSError(domain: "WebKitErrorDomain", code: 102, userInfo: [NSURLErrorFailingURLErrorKey: url])
        #expect(PageLoadError.from(interrupted, for: url) == nil)
    }

    @Test("Refused localhost names the server and hints at dev")
    func localhostRefused() {
        let (error, url) = failure(code: NSURLErrorCannotConnectToHost)
        let page = PageLoadError.from(error, for: url)
        #expect(page?.url == url)
        #expect(page?.title == "Couldn't connect to the server")
        #expect(page?.message.contains("running") == true)
    }

    @Test("Refused public host has no dev hint")
    func publicRefused() {
        let (error, url) = failure(code: NSURLErrorCannotConnectToHost, url: "https://example.com/")
        #expect(PageLoadError.from(error, for: url)?.message.contains("running") == false)
    }

    @Test("Offline, missing, and unknown failures map")
    func mappedFailures() {
        let (offline, offlineURL) = failure(code: NSURLErrorNotConnectedToInternet, url: "https://example.com/")
        #expect(PageLoadError.from(offline, for: offlineURL)?.title == "You're offline")
        let (missing, missingURL) = failure(code: NSURLErrorCannotFindHost, url: "https://nosuchhost.invalid/")
        #expect(PageLoadError.from(missing, for: missingURL)?.title == "Server not found")
        let (weird, weirdURL) = failure(code: -9999, url: "https://example.com/")
        let fallback = PageLoadError.from(weird, for: weirdURL)
        #expect(fallback?.title == "Couldn't load this page")
        #expect(!(fallback?.message.isEmpty ?? true))
    }

    @MainActor
    @Test("A dead server produces an error page, not a blank tab")
    func deadServerErrorPage() async throws {        let tab = LeanTab(
            dataStore: .nonPersistent(),
            initialURL: nil,
            scrollbarStyle: .normal,
            adBlockingEnabled: false
        )
        let keepAlive = tab
        // A port this test owns, refused fast by an accept-and-close loop:
        // no dependency on the fixed discard port staying closed on every
        // machine this suite runs on.
        let (port, fd) = Self.refusedLoopbackServer()
        defer { if fd >= 0 { close(fd) } }
        tab.load(URL(string: "http://127.0.0.1:\(port)/")!)
        var ticks = 0
        while tab.pageError == nil, ticks < 150 {
            try await Task.sleep(for: .milliseconds(100))
            ticks += 1
            _ = keepAlive
        }
        let error = try #require(tab.pageError)
        #expect(error.url?.host == "127.0.0.1")
        #expect(!error.title.isEmpty)
    }

    @MainActor
    @Test("A refused https loopback URL is retried over plain http")
    func refusedHttpsFallsBackToHttp() async throws {
        let tab = LeanTab(
            dataStore: .nonPersistent(),
            initialURL: nil,
            scrollbarStyle: .normal,
            adBlockingEnabled: false
        )
        let keepAlive = tab
        let (port, fd) = Self.refusedLoopbackServer()
        defer { if fd >= 0 { close(fd) } }
        // Nothing speaks TLS on this port, but plain http answers refused
        // too — the point is the error page names the http address, proving
        // the retry happened instead of failing on https.
        tab.load(URL(string: "https://127.0.0.1:\(port)/")!)
        var ticks = 0
        while tab.pageError == nil, ticks < 250 {
            try await Task.sleep(for: .milliseconds(100))
            ticks += 1
            _ = keepAlive
        }
        let error = try #require(tab.pageError)
        #expect(error.url?.scheme == "http")
        #expect(error.url?.host == "127.0.0.1")
    }

    @MainActor
    @Test("A failed navigation keeps the attempted address on the tab")
    func failedNavigationKeepsURL() async throws {
        let tab = LeanTab(
            dataStore: .nonPersistent(),
            initialURL: nil,
            scrollbarStyle: .normal,
            adBlockingEnabled: false
        )
        let keepAlive = tab
        let (port, fd) = Self.refusedLoopbackServer()
        defer { if fd >= 0 { close(fd) } }
        let target = URL(string: "http://127.0.0.1:\(port)/")!
        tab.load(target)
        var ticks = 0
        while tab.pageError == nil, ticks < 150 {
            try await Task.sleep(for: .milliseconds(100))
            ticks += 1
            _ = keepAlive
        }
        _ = try #require(tab.pageError)
        // The omnibar, reload, and session restore all read tab.url —
        // a failure must not blank it.
        #expect(tab.url == target)
    }

    @MainActor
    @Test("Failed navigations stay out of history but keep the address")
    func failedNavigationNotInHistory() async throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (port, fd) = Self.refusedLoopbackServer()
        defer { if fd >= 0 { close(fd) } }
        let target = URL(string: "http://127.0.0.1:\(port)/")!
        store.newTab(url: target)
        var ticks = 0
        while store.selectedTab?.pageError == nil, ticks < 250 {
            try await Task.sleep(for: .milliseconds(100))
            ticks += 1
        }
        _ = try #require(store.selectedTab?.pageError)
        store.flushPendingPersist()
        #expect(store.historyItems.isEmpty)
        #expect(store.selectedTab?.url == target)
    }

    @MainActor
    @Test("An unresolvable https host keeps its https error page")
    func dnsFailureStaysHttps() async throws {
        let tab = LeanTab(
            dataStore: .nonPersistent(),
            initialURL: nil,
            scrollbarStyle: .normal,
            adBlockingEnabled: false
        )
        let keepAlive = tab
        // `.invalid` never resolves: CannotFindHost is not a TLS failure,
        // so no http retry — the page must describe the https address.
        tab.load(URL(string: "https://nosuchhost.invalid/")!)
        var ticks = 0
        while tab.pageError == nil, ticks < 150 {
            try await Task.sleep(for: .milliseconds(100))
            ticks += 1
            _ = keepAlive
        }
        let error = try #require(tab.pageError)
        #expect(error.url?.scheme == "https")
        #expect(error.title == "Server not found")
    }
}
