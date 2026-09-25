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
}
