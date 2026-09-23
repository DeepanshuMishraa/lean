import Foundation
import Testing
@testable import Lean

struct PasswordVaultTests {
    @Test("Credential matching is restricted to the exact normalized origin")
    func exactOriginMatching() throws {
        let login = SavedPassword(
            scheme: "https",
            host: "example.com",
            port: nil,
            username: "alice",
            createdAt: nil
        )
        #expect(PasswordVault.matchesOrigin(login, try #require(URL(string: "https://EXAMPLE.com/account"))))
        #expect(PasswordVault.matchesOrigin(login, try #require(URL(string: "https://example.com:443/account"))))
        #expect(!PasswordVault.matchesOrigin(login, try #require(URL(string: "http://example.com/"))))
        #expect(!PasswordVault.matchesOrigin(login, try #require(URL(string: "https://sub.example.com/"))))
        #expect(!PasswordVault.matchesOrigin(login, try #require(URL(string: "https://example.com:8443/"))))
    }

    @Test("Default ports normalize to their standard origin")
    func normalizesDefaultPorts() throws {
        #expect(PasswordVault.originString(for: try #require(URL(string: "https://example.com:443/login"))) == "https://example.com")
        #expect(PasswordVault.originString(for: try #require(URL(string: "http://example.com:80/login"))) == "http://example.com")
    }

    @Test("Password origins reject non-web schemes")
    func rejectsNonWebOrigins() throws {
        #expect(PasswordVault.originString(for: try #require(URL(string: "file:///tmp/passwords"))) == nil)
        #expect(PasswordVault.normalizedHost("bad/host") == nil)
    }
}
