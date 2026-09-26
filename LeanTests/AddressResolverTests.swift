import Foundation
import Testing
@testable import Lean

struct AddressResolverTests {
    @Test("Resolves addresses and searches", arguments: [
        ("example.com", "https://example.com"),
        ("https://example.com/path", "https://example.com/path"),
        ("localhost:8080", "http://localhost:8080"),
        ("http://localhost:3000", "http://localhost:3000"),
        ("127.0.0.1:3000", "http://127.0.0.1:3000"),
        ("http://127.0.0.1:3000", "http://127.0.0.1:3000"),
        // LAN/private IPs and local names are http-only far more often
        // than not: a bare host must not become an https failure page.
        ("100.109.113.4", "http://100.109.113.4"),
        ("100.109.113.4:8000", "http://100.109.113.4:8000"),
        ("192.168.1.10", "http://192.168.1.10"),
        ("172.16.5.4", "http://172.16.5.4"),
        ("8.8.8.8", "http://8.8.8.8"),
        ("myserver.local", "http://myserver.local"),
        ("minimal mac browser", "https://www.google.com/search?q=minimal%20mac%20browser")
    ])
    func resolves(input: String, expected: String) {
        // Given, when
        let url = AddressResolver.resolve(input)

        // Then
        #expect(url?.absoluteString == expected)
    }

    @Test("Rejects blank input")
    func rejectsBlankInput() {
        // Given, when
        let url = AddressResolver.resolve("   ")

        // Then
        #expect(url == nil)
    }

    @Test("Loopback server addresses", arguments: [
        ("localhost:3000", "http://localhost:3000"),
        ("127.0.0.1:8000", "http://127.0.0.1:8000"),
        ("http://localhost:3000", "http://localhost:3000"),
        ("LOCALHOST:3000", "http://LOCALHOST:3000"),
        ("localhost:3000/api?q=1", "http://localhost:3000/api?q=1")
    ])
    func loopbackServer(input: String, expected: String) {
        #expect(AddressResolver.loopbackServerURL(from: input)?.absoluteString == expected)
    }

    @Test("Bare hosts and non-local ports are not server addresses")
    func notLoopbackServer() {
        #expect(AddressResolver.loopbackServerURL(from: "localhost") == nil)
        #expect(AddressResolver.loopbackServerURL(from: "127.0.0.1") == nil)
        #expect(AddressResolver.loopbackServerURL(from: "example.com:8080") == nil)
        #expect(AddressResolver.loopbackServerURL(from: "localhost:abc") == nil)
        #expect(AddressResolver.loopbackServerURL(from: "hello world") == nil)
    }

    @Test("Loopback URL detection")
    func loopbackURLs() {
        #expect(AddressResolver.isLoopbackURL(URL(string: "http://localhost:3000")!))
        #expect(AddressResolver.isLoopbackURL(URL(string: "http://127.0.0.1/")!))
        #expect(!AddressResolver.isLoopbackURL(URL(string: "https://example.com/")!))
        #expect(!AddressResolver.isLoopbackURL(URL(string: "https://duckduckgo.com/?q=localhost")!))
    }

    @Test("Public hostnames sharing private prefixes stay public")
    func privatePrefixLookalikes() {
        #expect(!AddressResolver.isLoopbackURL(URL(string: "https://10.com/")!))
        #expect(!AddressResolver.isLoopbackURL(URL(string: "https://192.168.com/")!))
        #expect(!AddressResolver.isLoopbackURL(URL(string: "https://10.example.com/")!))
        #expect(AddressResolver.loopbackServerURL(from: "10.0.0.5:3000")?.absoluteString == "http://10.0.0.5:3000")
        #expect(AddressResolver.loopbackServerURL(from: "192.168.1.10:8080")?.absoluteString == "http://192.168.1.10:8080")
        #expect(AddressResolver.loopbackServerURL(from: "10.com:8080") == nil)
    }

    @Test("CGNAT, office, and link-local ranges resolve to http")
    func privateRangesResolveToHttp() {
        #expect(AddressResolver.webURL(from: "100.109.113.4")?.absoluteString == "http://100.109.113.4")
        #expect(AddressResolver.webURL(from: "172.31.255.1:8080")?.absoluteString == "http://172.31.255.1:8080")
        #expect(AddressResolver.webURL(from: "169.254.10.20")?.absoluteString == "http://169.254.10.20")
        // Any bare IPv4 literal defaults to http (https to a raw IP
        // almost never has a valid certificate); public domains keep https.
        #expect(AddressResolver.webURL(from: "172.15.0.1")?.absoluteString == "http://172.15.0.1")
        #expect(AddressResolver.webURL(from: "example.com")?.absoluteString == "https://example.com")
        #expect(AddressResolver.loopbackServerURL(from: "100.109.113.4:3000")?.absoluteString == "http://100.109.113.4:3000")
    }

    @Test("Local names and suffixes resolve to http")
    func localNamesResolveToHttp() {
        #expect(AddressResolver.webURL(from: "myserver.local")?.absoluteString == "http://myserver.local")
        #expect(AddressResolver.webURL(from: "printer.lan:631")?.absoluteString == "http://printer.lan:631")
        // Explicit schemes are never rewritten.
        #expect(AddressResolver.webURL(from: "https://example.com")?.absoluteString == "https://example.com")
        #expect(AddressResolver.webURL(from: "http://100.109.113.4/")?.absoluteString == "http://100.109.113.4/")
    }

    @Test("IP literals are navigation-only, never search", arguments: [
        ("100.109.113.4", "http://100.109.113.4"),
        ("100.109.113.4:8000", "http://100.109.113.4:8000"),
        ("100.109.113.4:8000/status?x=1", "http://100.109.113.4:8000/status?x=1"),
        ("http://100.109.113.4/", "http://100.109.113.4/"),
        ("https://100.109.113.4/", "https://100.109.113.4/"),
        ("[fd00::1]:3000", "http://[fd00::1]:3000"),
    ])
    func ipLiteralURL(input: String, expected: String) {
        #expect(AddressResolver.ipLiteralURL(from: input)?.absoluteString == expected)
    }

    @Test("Domains and search text are not IP literals")
    func nonIPLiterals() {
        #expect(AddressResolver.ipLiteralURL(from: "example.com") == nil)
        #expect(AddressResolver.ipLiteralURL(from: "example.com:8080") == nil)
        #expect(AddressResolver.ipLiteralURL(from: "minimal mac browser") == nil)
        #expect(AddressResolver.ipLiteralURL(from: "ftp://1.2.3.4/") == nil)
        #expect(AddressResolver.ipLiteralURL(from: "localhost:3000") == nil)
        #expect(AddressResolver.ipLiteralURL(from: "") == nil)
    }
}
