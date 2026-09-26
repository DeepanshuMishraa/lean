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

    @Test("IPv6 origins normalize with brackets")
    func normalizesIPv6() throws {
        let origin = try #require(URL(string: "https://[2001:db8::1]:8443/login"))
        #expect(PasswordVault.originString(for: origin) == "https://[2001:db8::1]:8443")
    }

    @Test("Registrable domains group a site's hosts")
    func registrableDomains() {
        #expect(PasswordVault.registrableHost("example.com") == "example.com")
        #expect(PasswordVault.registrableHost("www.example.com") == "example.com")
        #expect(PasswordVault.registrableHost("accounts.example.com") == "example.com")
        #expect(PasswordVault.registrableHost("a.b.example.com") == "example.com")
        #expect(PasswordVault.registrableHost("example.co.uk") == "example.co.uk")
        #expect(PasswordVault.registrableHost("www.bbc.co.uk") == "bbc.co.uk")
        #expect(PasswordVault.registrableHost("localhost") == "localhost")
        #expect(PasswordVault.registrableHost("EXAMPLE.COM") == "example.com")
        #expect(PasswordVault.registrableHost("evil-example.com") == "evil-example.com")
        #expect(PasswordVault.registrableHost("example.com.evil.com") == "evil.com")
    }

    @Test("Multi-tenant suffixes keep tenants apart")
    func tenantIsolation() {
        #expect(PasswordVault.registrableHost("foo.github.io") == "foo.github.io")
        #expect(PasswordVault.registrableHost("bar.github.io") == "bar.github.io")
        #expect(PasswordVault.registrableHost("github.io") == "github.io")
        let kept = SavedPassword(scheme: "https", host: "foo.github.io", port: nil, username: "alice", createdAt: nil)
        #expect(PasswordVault.isOffered(kept, onHost: "foo.github.io", scheme: "https"))
        #expect(!PasswordVault.isOffered(kept, onHost: "bar.github.io", scheme: "https"))
        #expect(!PasswordVault.isOffered(kept, onHost: "github.io", scheme: "https"))
    }

    @Test("Regional S3 buckets stay distinct tenants")
    func s3TenantIsolation() {
        #expect(
            PasswordVault.registrableHost("alice.s3.us-west-2.amazonaws.com")
                == "alice.s3.us-west-2.amazonaws.com"
        )
        let kept = SavedPassword(scheme: "https", host: "alice.s3.us-west-2.amazonaws.com", port: nil, username: "alice", createdAt: nil)
        #expect(PasswordVault.isOffered(kept, onHost: "alice.s3.us-west-2.amazonaws.com", scheme: "https"))
        #expect(!PasswordVault.isOffered(kept, onHost: "bob.s3.us-west-2.amazonaws.com", scheme: "https"))
        #expect(!PasswordVault.isOffered(kept, onHost: "alice.s3.us-east-1.amazonaws.com", scheme: "https"))
    }

    @Test("Password origins reject non-web schemes")
    func rejectsNonWebOrigins() throws {
        #expect(PasswordVault.originString(for: try #require(URL(string: "file:///tmp/passwords"))) == nil)
        #expect(PasswordVault.normalizedHost("bad/host") == nil)
    }

    @Test("Offering stays on the site and on the scheme it was kept from")
    func offeringScope() {
        let kept = SavedPassword(scheme: "https", host: "example.com", port: nil, username: "alice", createdAt: nil)
        #expect(PasswordVault.isOffered(kept, onHost: "example.com", scheme: "https"))
        #expect(PasswordVault.isOffered(kept, onHost: "accounts.example.com", scheme: "https"))
        // An http page is offered only what was kept from http.
        #expect(!PasswordVault.isOffered(kept, onHost: "example.com", scheme: "http"))
        #expect(!PasswordVault.isOffered(kept, onHost: "accounts.example.com", scheme: "http"))
        let httpKept = SavedPassword(scheme: "http", host: "example.com", port: nil, username: "bob", createdAt: nil)
        #expect(PasswordVault.isOffered(httpKept, onHost: "example.com", scheme: "http"))
        #expect(!PasswordVault.isOffered(httpKept, onHost: "example.com", scheme: "https"))
        // Another site never qualifies, whatever the scheme.
        #expect(!PasswordVault.isOffered(kept, onHost: "evil.com", scheme: "https"))
        #expect(!PasswordVault.isOffered(kept, onHost: "example.com.evil.com", scheme: "https"))
    }
}
