import Foundation
import Testing
@testable import Lean

struct PasskeyEncodingTests {
    @Test("base64url text round-trips through data")
    func roundTrip() {
        let original = Data([0, 1, 2, 250, 251, 252, 253, 254, 255])
        let encoded = Passkeys.text(original)
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
        #expect(Passkeys.data(encoded) == original)
    }

    @Test("unpadded and URL-safe input decodes")
    func urlSafeInput() {
        #expect(Passkeys.data("aGk") == Data("hi".utf8))
        #expect(Passkeys.data("aGk=") == Data("hi".utf8))
        #expect(Passkeys.data("--__") == Data([0xFB, 0xEF, 0xFF]))
    }

    @Test("non-strings and garbage give nil")
    func invalidInput() {
        #expect(Passkeys.data(nil) == nil)
        #expect(Passkeys.data(42) == nil)
        #expect(Passkeys.data("!!!") == nil)
    }

    @Test("failure reply carries the error name and message")
    func failureShape() {
        let reply = Passkeys.failure("NotAllowedError", "nope")
        #expect(reply["error"] as? String == "NotAllowedError")
        #expect(reply["message"] as? String == "nope")
    }
}

struct PasskeyRelyingPartyTests {
    @Test("the page's own host always fits")
    func ownHost() {
        #expect(Passkeys.fits("example.com", "example.com"))
        #expect(Passkeys.fits("127.0.0.1", "127.0.0.1"))
    }

    @Test("a registrable domain above the host fits")
    func parentDomain() {
        #expect(Passkeys.fits("example.com", "login.example.com"))
    }

    @Test("another site never fits")
    func otherSite() {
        #expect(!Passkeys.fits("other.com", "login.example.com"))
        #expect(!Passkeys.fits("example.com.evil.com", "login.example.com"))
    }

    @Test("a bare suffix anyone can register under never fits")
    func publicSuffix() {
        #expect(!Passkeys.fits("com", "foo.com"))
        #expect(!Passkeys.fits("github.io", "foo.github.io"))
    }

    @Test("an address only fits itself")
    func address() {
        #expect(!Passkeys.fits("0.0.1", "10.0.0.1"))
    }
}

struct PasskeyAttestationTests {
    /// An attestation object in the shape a real ceremony returns: a CBOR
    /// map with the authenticator data under "authData", holding a P-256
    /// credential.
    private static func attestation() -> Data {
        let id = Data((0..<16).map { UInt8($0) })
        var auth = Data(count: 32) + Data([0x45]) + Data(count: 4)
        auth += Data(count: 16) + Data([0, UInt8(id.count)]) + id
        auth += Data([0xA5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21, 0x58, 0x20]) + Data(repeating: 1, count: 32)
        auth += Data([0x22, 0x58, 0x20]) + Data(repeating: 2, count: 32)
        var object = Data([0xA3, 0x63]) + Data("fmt".utf8) + Data([0x64]) + Data("none".utf8)
        object += Data([0x67]) + Data("attStmt".utf8) + Data([0xA0])
        object += Data([0x68]) + Data("authData".utf8) + Data([0x59, UInt8(auth.count >> 8), UInt8(auth.count & 0xFF)]) + auth
        return object
    }

    @Test("authenticator data comes back out of the attestation object")
    func authenticatorDataExtraction() {
        let object = Self.attestation()
        let auth = Passkeys.authenticatorData(inAttestation: object)
        #expect(auth != nil)
        #expect(auth!.count > 55)
        #expect(auth![32] & 0x40 != 0)
    }

    @Test("garbage is not authenticator data")
    func garbageRejected() {
        #expect(Passkeys.authenticatorData(inAttestation: Data([1, 2, 3])) == nil)
        #expect(Passkeys.authenticatorData(inAttestation: Data()) == nil)
    }

    @Test("a P-256 key reads out as DER with algorithm -7")
    func p256PublicKey() throws {
        let auth = Passkeys.authenticatorData(inAttestation: Self.attestation())!
        let key = Passkeys.publicKey(inAuthenticatorData: auth)
        #expect(key?.algorithm == -7)
        let der = try #require(key?.der)
        #expect(der.count == 91)
        #expect(Array(der.prefix(2)) == [0x30, 0x59])
        #expect(Array(der.suffix(64)) == Array(repeating: 1, count: 32) + Array(repeating: 2, count: 32))
    }

    @Test("registration reply embeds authenticator data and the DER key")
    func registrationReply() throws {
        let object = Self.attestation()
        let reply = Passkeys.registrationReply(
            id: Data([9]), clientData: Data([8]), attestation: object,
            transports: ["hybrid", "internal"], attachment: "platform"
        )
        #expect(reply["kind"] as? String == "create")
        #expect(reply["publicKeyAlgorithm"] as? Int == -7)
        let key = try #require(Passkeys.data(reply["publicKey"]))
        #expect(key.count == 91)
    }
}

struct CBORTests {
    @Test("maps, ints, text and blobs read")
    func primitives() {
        var reader = CBOR(bytes: [0xA2, 0x00, 0x01, 0x61, 0x61, 0x42, 0x01, 0x02])
        let count = reader.mapCount()
        let first = reader.int()
        let second = reader.int()
        let word = reader.text()
        let blob = reader.blob()
        #expect(count == 2)
        #expect(first == 0)
        #expect(second == 1)
        #expect(word == "a")
        #expect(blob == [0x01, 0x02])
    }

    @Test("negative ints read")
    func negative() {
        var reader = CBOR(bytes: [0x20, 0x29])
        let minusOne = reader.int()
        let minusTen = reader.int()
        #expect(minusOne == -1)
        #expect(minusTen == -10)
    }

    @Test("skip steps over nested values")
    func skipping() {
        var reader = CBOR(bytes: [0xA1, 0x61, 0x61, 0x82, 0x01, 0xA1, 0x00, 0x00])
        let count = reader.mapCount()
        let word = reader.text()
        let skipped = reader.skip()
        #expect(count == 1)
        #expect(word == "a")
        #expect(skipped)
    }

    @Test("truncated input fails instead of trapping")
    func truncated() {
        var reader = CBOR(bytes: [0xA2, 0x00])
        let count = reader.mapCount()
        let first = reader.int()
        let second = reader.int()
        #expect(count == 2)
        #expect(first == 0)
        #expect(second == nil)
    }
}

struct PasskeyRelayScriptTests {
    @Test("handler name and event names are stable")
    func names() {
        #expect(PasskeyRelay.name == "leanPasskeys")
        #expect(PasskeyRelay.asked == "lean-passkeys-ask")
        #expect(PasskeyRelay.answered == "lean-passkeys-answer")
    }

    @Test("page patch stands in for the platform's credentials")
    func pagePatch() {
        let script = PasskeyRelay.page
        #expect(script.contains("CredentialsContainer.prototype"))
        #expect(script.contains("Symbol.for('lean.passkeys')"))
        #expect(script.contains("lean-passkeys-ask"))
        #expect(script.contains("lean-passkeys-answer"))
        #expect(script.contains("isUserVerifyingPlatformAuthenticatorAvailable"))
        #expect(script.contains("getPublicKey"))
        // Nothing of Lean's leaks into the page's world: no webkit handle,
        // no Lean global — the bridge in Lean's world carries requests.
        #expect(!script.contains("webkit.messageHandlers"))
        #expect(!script.contains("__lean"))
    }

    @Test("bridge connects the page's events to the reply handler")
    func bridge() {
        let script = PasskeyRelay.bridge
        #expect(script.contains("webkit.messageHandlers.leanPasskeys"))
        #expect(script.contains("lean-passkeys-ask"))
        #expect(script.contains("lean-passkeys-answer"))
    }

    @Test("without-passkeys keeps passwords working, hides the object")
    func withoutPasskeys() {
        let script = PasskeyRelay.withoutPasskeys
        #expect(script.contains("PublicKeyCredential"))
        #expect(script.contains("CredentialsContainer.prototype"))
        #expect(script.contains("conditional"))
    }
}
