import Foundation
import Testing
@testable import Lean

struct AddressResolverTests {
    @Test("Resolves addresses and searches", arguments: [
        ("example.com", "https://example.com"),
        ("https://example.com/path", "https://example.com/path"),
        ("localhost:8080", "https://localhost:8080"),
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
}
