import Foundation
import Testing
@testable import Lean

struct PageLoadErrorTests {
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
        // Nothing listens on discard-port 9: connection refused, fast.
        tab.load(URL(string: "http://127.0.0.1:9/")!)
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
