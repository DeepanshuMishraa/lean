import Foundation
import Testing
@testable import Lean

struct ChromiumPasswordsTests {
    // Vectors generated independently with Python's `cryptography` package
    // (AES-128-CBC, IV of sixteen spaces, PKCS#7) and hashlib PBKDF2-HMAC-SHA1
    // ("saltysalt", 1003 rounds) — not with this code, so they pin the
    // Chromium recipe rather than echoing it.
    private static let passphrase = "lean-test-passphrase"
    private static let stretchedKey: [UInt8] = [
        0x4c, 0x1c, 0xad, 0x80, 0x57, 0x55, 0xcd, 0xe7,
        0x5f, 0x2a, 0xd7, 0x20, 0x78, 0x9b, 0xb7, 0x38,
    ]
    private static let blobHex = "76313048c5b1256b1c5cebb8685e04feaf4ffd"
    private static let password = "s3cret-p@ssw0rd"

    private static func blob() -> Data {
        var data = Data()
        var index = blobHex.startIndex
        while index < blobHex.endIndex {
            let next = blobHex.index(index, offsetBy: 2)
            data.append(UInt8(blobHex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    @Test("PBKDF2 stretching matches Chromium's recipe")
    func stretchesKey() {
        #expect(ChromiumPasswords.stretch(Self.passphrase) == Self.stretchedKey)
    }

    @Test("v10 blobs unwrap with the stretched key")
    func unwrapsBlob() {
        #expect(ChromiumPasswords.unwrap(Self.blob(), key: Self.stretchedKey) == Self.password)
    }

    @Test("Stretch then unwrap round-trips")
    func roundTrips() {
        #expect(ChromiumPasswords.stretch(Self.passphrase) == Self.stretchedKey)
        #expect(ChromiumPasswords.unwrap(Self.blob(), key: ChromiumPasswords.stretch(Self.passphrase)) == Self.password)
    }

    @Test("Wrong keys fail instead of returning junk")
    func rejectsBadInput() {
        #expect(ChromiumPasswords.unwrap(Self.blob(), key: [UInt8](repeating: 0, count: 16)) == nil)
        #expect(ChromiumPasswords.unwrap(Self.blob(), key: [UInt8](repeating: 7, count: 16)) == nil)
    }

    @Test("Plaintext blobs from very old profiles pass through")
    func passesPlaintextThrough() {
        #expect(ChromiumPasswords.unwrap(Data("old-secret".utf8), key: Self.stretchedKey) == "old-secret")
        #expect(ChromiumPasswords.unwrap(Data("short".utf8), key: Self.stretchedKey) == "short")
    }

    @Test("Helium uses its own data folder and keychain names")
    func heliumDescriptors() {
        // Per imputnet/helium-macos patches via driceroland/Search#178.
        #expect(BrowserImportSource.helium.userDataDirectory.lastPathComponent == "net.imput.helium")
        #expect(BrowserImportSource.helium.keychainService == "Helium Storage Key")
        #expect(BrowserImportSource.helium.keychainAccount == "Helium")
        #expect(BrowserImportSource.helium.hasLoginData)
    }

    @Test("Every supported browser resolves to its real folder and key")
    func supportedBrowserDescriptors() {
        // Folder layouts and keychain names verified against real installs
        // (Arc, Dia, Helium on disk; Chrome is Chromium-standard and matches
        // Search's production list). If any of these drift, that browser's
        // import silently finds nothing.
        let expected: [(BrowserImportSource, String, String, String)] = [
            (.chrome, "Google/Chrome", "Chrome Safe Storage", "Chrome"),
            (.arc, "Arc/User Data", "Arc Safe Storage", "Arc"),
            (.dia, "Dia/User Data", "Dia Safe Storage", "Dia"),
            (.helium, "net.imput.helium", "Helium Storage Key", "Helium"),
        ]
        for (source, folder, service, account) in expected {
            #expect(source.displayDataDirectory.path.hasSuffix("Library/Application Support/\(folder)"), "\(source) folder")
            #expect(source.keychainService == service, "\(source) service")
            #expect(source.keychainAccount == account, "\(source) account")
            #expect(source.hasLoginData)
        }
    }
}
