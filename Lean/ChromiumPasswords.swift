import CommonCrypto
import Foundation
import Security
import SQLite3

// Reading the passwords another Chromium browser on this Mac already holds.
//
// Every Chromium browser — Chrome, Dia, Arc, Brave, Edge, Helium, the rest —
// keeps its passwords the same way: a SQLite file called "Login Data", each
// password encrypted with a key the browser itself keeps in the macOS
// keychain under "<Name> Safe Storage" (Helium: "Helium Storage Key").
// macOS asks you before handing that key to anyone else, which is the one
// thing here you have to say yes to. After that it is arithmetic: the key is
// stretched the way Chromium stretches it (PBKDF2/SHA-1, "saltysalt", 1003
// rounds), and each password is unwrapped (AES-128-CBC, "v10" prefix, an IV
// of sixteen spaces) and written to the keychain under Lean's name instead.
//
// The file is copied before it is read. The browser it belongs to is usually
// running, and reading its live database underneath it is how you get a lock
// error, or worse, its attention.
//
// Ported from Search's Import.swift (Sources/Search/Import.swift); the Helium
// keychain names come from imputnet/helium-macos
// (change-keychain-name.patch: service "Helium Storage Key", account
// "Helium") via driceroland/Search#178.
enum ChromiumPasswords {
    struct Login {
        let origin: String
        let user: String
        let password: String
    }

    enum PasswordError: LocalizedError, Equatable {
        /// The keychain didn't hand over the browser's Safe Storage key —
        /// macOS refused, or there is nothing to read.
        case noPassphrase
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noPassphrase:
                "macOS didn't hand over the key — allow it and try again."
            case .unreadable:
                "Lean couldn't read the browser's saved passwords. If that browser is open, quit it and try again."
            }
        }
    }

    /// Every "Login Data" file under a granted browser data folder, not only
    /// the default profile's. `directory` must be directly readable — through
    /// a folder the user picked (security-scoped grant), or the browser's own
    /// data folder when the sandbox lets us in.
    static func read(in directory: URL, source: BrowserImportSource) throws -> [Login] {
        guard let service = source.keychainService, let account = source.keychainAccount else {
            throw PasswordError.unreadable
        }
        guard let passphrase = safeStorage(service: service, account: account) else {
            throw PasswordError.noPassphrase
        }
        let key = stretch(passphrase)

        var logins: [Login] = []
        var seen = Set<String>()
        var readAny = false
        for file in loginDataFiles(in: directory) {
            guard let rows = try? rows(in: file) else { continue }
            readAny = true
            for row in rows {
                // Sites the other browser was told never to ask about stay
                // behind; Lean has no never-ask list to put them in.
                guard !row.never else { continue }
                guard let password = unwrap(row.blob, key: key), !password.isEmpty else { continue }
                let id = "\(row.origin)\u{1}\(row.user)"
                guard seen.insert(id).inserted else { continue }
                logins.append(Login(origin: row.origin, user: row.user, password: password))
            }
        }
        guard readAny else { throw PasswordError.unreadable }
        return logins
    }

    // MARK: - discovery

    private static func loginDataFiles(in directory: URL) -> [URL] {
        // The granted folder itself may be a profile (has Login Data next to
        // Bookmarks/History), or a User Data root holding several profiles.
        var found: [URL] = []
        guard let walk = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        for case let url as URL in walk {
            // Three levels is as deep as a profile goes; going further is a
            // walk through the cache.
            if url.pathComponents.count - directory.pathComponents.count > 3 {
                walk.skipDescendants()
                continue
            }
            if url.lastPathComponent == "Login Data" { found.append(url) }
        }
        return found
    }

    // MARK: - the key

    private static func safeStorage(service: String, account: String) -> String? {
        var out: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data,
              let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return nil }
        return text
    }

    /// Chromium's own recipe, unchanged for a decade: PBKDF2 over SHA-1, the
    /// salt "saltysalt", 1003 rounds, sixteen bytes out.
    static func stretch(_ passphrase: String) -> [UInt8] {
        var key = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8)
        let pass = Array(passphrase.utf8)
        pass.withUnsafeBufferPointer { p in
            salt.withUnsafeBufferPointer { s in
                _ = CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    UnsafeRawPointer(p.baseAddress!).assumingMemoryBound(to: Int8.self), pass.count,
                    s.baseAddress!, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                    &key, key.count
                )
            }
        }
        return key
    }

    /// "v10" and then AES-128-CBC with an IV of sixteen spaces.
    static func unwrap(_ blob: Data, key: [UInt8]) -> String? {
        guard blob.count > 3, blob.prefix(3) == Data("v10".utf8) else {
            // Not encrypted at all, on some very old profiles.
            return String(data: blob, encoding: .utf8)
        }
        let body = [UInt8](blob.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: 16)
        var out = [UInt8](repeating: 0, count: body.count + kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(
            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
            key, key.count, iv,
            body, body.count,
            &out, out.count, &moved
        )
        guard status == kCCSuccess else { return nil }
        let plain = Data(out.prefix(moved))
        if let text = String(data: plain, encoding: .utf8) { return text }
        // Newer builds prefix the password with a hash of the site. Past it,
        // the password is the same as ever.
        guard plain.count > 32 else { return nil }
        return String(data: plain.dropFirst(32), encoding: .utf8)
    }

    // MARK: - the file

    private struct Row {
        let origin: String
        let user: String
        let blob: Data
        let never: Bool
    }

    private static func rows(in file: URL) throws -> [Row] {
        // A copy, next to nothing the other browser is watching.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lean-import-\(UUID().uuidString).db")
        try FileManager.default.copyItem(at: file, to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(temp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw PasswordError.unreadable
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT origin_url, username_value, password_value, blacklisted_by_user
        FROM logins
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PasswordError.unreadable
        }
        defer { sqlite3_finalize(statement) }

        var out: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let origin = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let user = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            var blob = Data()
            if let bytes = sqlite3_column_blob(statement, 2) {
                blob = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
            }
            let never = sqlite3_column_int(statement, 3) != 0
            out.append(Row(origin: origin, user: user, blob: blob, never: never))
        }
        return out
    }
}
