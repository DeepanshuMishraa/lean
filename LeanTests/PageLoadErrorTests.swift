import Foundation
import Testing
@testable import Lean

struct PageLoadErrorTests {
    /// A loopback port nothing listens on: bind an ephemeral port, read it
    /// back, and close it. Connecting there refuses fast, with a port the
    /// test owns instead of a fixed one.
    nonisolated static func closedLoopbackPort() -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 9 }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        guard withUnsafeMutablePointer(to: &addr, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }) == 0 else { return 9 }
        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &len) }
        }
        let port = CFSwapInt16BigToHost(actual.sin_port)
        return port == 0 ? 9 : port
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
    func deadServerErrorPage() async throws {
        let tab = LeanTab(
            dataStore: .nonPersistent(),
            initialURL: nil,
            scrollbarStyle: .normal,
            adBlockingEnabled: false
        )
        let keepAlive = tab
        // A port this test owns and closes: connecting there reliably
        // refuses, without depending on the fixed discard port staying
        // closed on every machine this suite runs on.
        let port = Self.closedLoopbackPort()
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
}
