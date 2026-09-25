import Foundation
import LocalAuthentication
import Security

struct SavedPassword: Identifiable, Hashable {
    let scheme: String
    let host: String
    let port: Int?
    let username: String
    let createdAt: Date?
    /// When it was last used to fill a sign-in, if known. Rides in the
    /// Keychain item's comment field. Newest first in suggestion lists.
    var lastUsed: Date? = nil

    var origin: String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.string ?? "\(scheme)://\(host)"
    }

    var id: String { "\(origin)\u{1}\(username)" }
}

enum PasswordVault {
    enum VaultError: LocalizedError, Equatable {
        case invalidOrigin
        case notFound
        case invalidEncoding
        case keychain(Int32)

        var errorDescription: String? {
            switch self {
            case .invalidOrigin: "Enter a valid HTTP or HTTPS website address."
            case .notFound: "The saved password is no longer in the Keychain."
            case .invalidEncoding: "The saved password could not be read."
            case .keychain(let status): "Keychain operation failed (\(status)). Check Keychain access and try again."
            }
        }
    }

    static let didChange = Notification.Name("LeanPasswordVaultDidChange")
    private static let label = "Lean"
    /// Short-lived cache: every password-field focus and every right-click
    /// was doing a full synchronous Keychain dump + decode + sort on the
    /// main thread. Cache for 15s; writes invalidate immediately.
    private static var allCache: (logins: [SavedPassword], at: Date)?
    private static let cacheTTL: TimeInterval = 15

    static func normalizedHost(_ host: String) -> String? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty,
              host.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\@%?#")) == nil,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: "https://\(host.contains(":") ? "[\(host)]" : host)"),
              components.query == nil,
              components.fragment == nil,
              components.user == nil,
              components.host != nil else { return nil }
        return components.host?.lowercased()
    }

    private static func normalizedOrigin(_ origin: URL) -> (scheme: String, host: String, port: Int?)? {
        let scheme = origin.scheme?.lowercased()
        guard let scheme, ["http", "https"].contains(scheme),
              let rawHost = origin.host,
              let host = normalizedHost(rawHost) else { return nil }
        let port = (scheme == "https" && origin.port == 443) || (scheme == "http" && origin.port == 80)
            ? nil
            : origin.port
        return (scheme, host, port)
    }

    static func originString(for origin: URL) -> String? {
        guard let normalized = normalizedOrigin(origin) else { return nil }
        var components = URLComponents()
        components.scheme = normalized.scheme
        components.host = normalized.host
        components.port = normalized.port
        return components.string
    }

    static func originURL(for origin: URL) -> URL? {
        guard let string = originString(for: origin) else { return nil }
        return URL(string: string)
    }

    private static func protocolValue(_ scheme: String) -> String {
        scheme == "https" ? kSecAttrProtocolHTTPS as String : kSecAttrProtocolHTTP as String
    }

    private static func identity(_ login: SavedPassword) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: login.host,
            kSecAttrProtocol as String: protocolValue(login.scheme),
            kSecAttrAccount as String: login.username,
            kSecAttrLabel as String: label,
        ]
        if let port = login.port { query[kSecAttrPort as String] = port }
        return query
    }

    static func all() -> Result<[SavedPassword], VaultError> {
        if let cache = allCache, Date().timeIntervalSince(cache.at) < cacheTTL {
            return .success(cache.logins)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: label,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            // Cache the empty vault too: without it every focus and
            // right-click repeats the synchronous Keychain round-trip.
            allCache = ([], Date())
            return .success([])
        }
        guard status == errSecSuccess else { return .failure(.keychain(status)) }
        let attributes = result as? [[String: Any]] ?? []
        let logins = attributes.compactMap { item -> SavedPassword? in
            guard let rawHost = item[kSecAttrServer as String] as? String,
                  let host = normalizedHost(rawHost),
                  let username = item[kSecAttrAccount as String] as? String else { return nil }
            let protocolName = item[kSecAttrProtocol as String] as? String
            let scheme: String
            if protocolName == kSecAttrProtocolHTTP as String {
                scheme = "http"
            } else if protocolName == kSecAttrProtocolHTTPS as String || protocolName == nil {
                // Phase 1 imports stored only the host; treat those legacy entries as HTTPS.
                scheme = "https"
            } else {
                return nil
            }
            let rawPort = item[kSecAttrPort as String] as? Int
            let port = (scheme == "https" && rawPort == 443) || (scheme == "http" && rawPort == 80) ? nil : rawPort
            let lastUsed = (item[kSecAttrComment as String] as? String)
                .flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
            return SavedPassword(
                scheme: scheme,
                host: host,
                port: port,
                username: username,
                createdAt: item[kSecAttrCreationDate as String] as? Date,
                lastUsed: lastUsed
            )
        }
        let sorted = logins.sorted { ($0.origin, $0.username) < ($1.origin, $1.username) }
        allCache = (sorted, Date())
        return .success(sorted)
    }

    static func matchesOrigin(_ login: SavedPassword, _ origin: URL) -> Bool {
        guard let normalized = normalizedOrigin(origin) else { return false }
        return login.scheme == normalized.scheme && login.host == normalized.host && login.port == normalized.port
    }

    static func forOrigin(_ origin: URL) -> Result<[SavedPassword], VaultError> {
        guard normalizedOrigin(origin) != nil else { return .failure(.invalidOrigin) }
        return all().map { $0.filter { matchesOrigin($0, origin) } }
    }

    /// example.com for www.example.com and accounts.example.com; bbc.co.uk
    /// stays bbc.co.uk. The handful of two-part endings that matter here are
    /// listed; a full public suffix list would be a library for a corner.
    static func registrableHost(_ host: String) -> String {
        let labels = host.lowercased().split(separator: ".").map(String.init)
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let seconds: Set<String> = ["co", "com", "org", "net", "gov", "gouv", "ac", "edu", "asso", "or", "ne"]
        if seconds.contains(labels[labels.count - 2]), labels[labels.count - 1].count == 2 {
            return labels.suffix(3).joined(separator: ".")
        }
        return labels.suffix(2).joined(separator: ".")
    }

    /// Whether a kept login may be offered on a page: the same registrable
    /// site, and the same scheme — an http page is offered only what was
    /// kept from http, never a password saved over https.
    static func isOffered(_ login: SavedPassword, onHost host: String, scheme: String) -> Bool {
        guard login.scheme == scheme else { return false }
        return login.host == host || registrableHost(login.host) == registrableHost(host)
    }

    /// Logins kept for the site behind an origin: the exact host first, then
    /// anything sharing its registrable domain. A sign-in rarely lives on the
    /// page it was saved from — accounts.example.com asks, and the password
    /// was kept for example.com — so the autofill prompt matches as a site,
    /// not as an exact scheme/host/port triple. Filling still asks Touch ID
    /// every time.
    static func forSite(_ origin: URL) -> Result<[SavedPassword], VaultError> {
        guard let normalized = normalizedOrigin(origin) else { return .failure(.invalidOrigin) }
        return all().map { logins in
            let offered = logins.filter { isOffered($0, onHost: normalized.host, scheme: normalized.scheme) }
            let exact = offered.filter { $0.host == normalized.host }
            let wider = offered.filter { $0.host != normalized.host }
            return (exact + wider).sorted {
                let exactLHS = $0.host == normalized.host
                let exactRHS = $1.host == normalized.host
                if exactLHS != exactRHS { return exactLHS }
                let usedLHS = $0.lastUsed ?? .distantPast
                let usedRHS = $1.lastUsed ?? .distantPast
                if usedLHS != usedRHS { return usedLHS > usedRHS }
                return ($0.origin, $0.username) < ($1.origin, $1.username)
            }
        }
    }

    /// Marks a login as just used so suggestion lists put it first.
    static func touch(_ login: SavedPassword) {
        let update: [String: Any] = [
            kSecAttrComment as String: String(Date().timeIntervalSince1970),
        ]
        SecItemUpdate(identity(login) as CFDictionary, update as CFDictionary)
        allCache = nil
    }

    static func save(origin: URL, username: String, password: String) -> Result<Void, VaultError> {
        guard let normalized = normalizedOrigin(origin) else { return .failure(.invalidOrigin) }
        let login = SavedPassword(
            scheme: normalized.scheme,
            host: normalized.host,
            port: normalized.port,
            username: username,
            createdAt: nil
        )
        let data = Data(password.utf8)
        let stamp = String(Date().timeIntervalSince1970)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrComment as String: stamp,
            kSecAttrLabel as String: label,
        ]
        // 1. Our own item, if present.
        var status = SecItemUpdate(identity(login) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            allCache = nil
            NotificationCenter.default.post(name: didChange, object: nil)
            return .success(())
        }
        // 2. Anything else kept for this server + account: legacy items
        // without a protocol, or ones Safari/Chrome/Search saved. Adopting in
        // place is what avoids errSecDuplicateItem (-25299) on Add below —
        // the update misses them, but the add still collides with them.
        // (Adopting another app's item is also the moment macOS shows the
        // keychain access prompt.)
        let broad: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: login.host,
            kSecAttrAccount as String: username,
        ]
        status = SecItemUpdate(broad as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            allCache = nil
            NotificationCenter.default.post(name: didChange, object: nil)
            return .success(())
        }
        // 3. Brand new.
        var add = identity(login)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        add[kSecAttrComment as String] = stamp
        status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess {
            allCache = nil
            NotificationCenter.default.post(name: didChange, object: nil)
            return .success(())
        }
        // 4. Twins our queries couldn't see through (port/protocol variants):
        // converge them into the just-submitted password rather than failing.
        SecItemDelete(broad as CFDictionary)
        status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { return .failure(.keychain(status)) }
        allCache = nil
        NotificationCenter.default.post(name: didChange, object: nil)
        return .success(())
    }

    static func password(for login: SavedPassword) -> Result<String, VaultError> {
        var query = identity(login)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound, login.scheme == "https", login.port == nil {
            var legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: login.host,
                kSecAttrAccount as String: login.username,
                kSecAttrLabel as String: label,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
        }
        guard status == errSecSuccess, let data = result as? Data else {
            return .failure(status == errSecItemNotFound ? .notFound : .keychain(status))
        }
        guard let password = String(data: data, encoding: .utf8) else { return .failure(.invalidEncoding) }
        return .success(password)
    }

    static func remove(_ login: SavedPassword) -> Result<Void, VaultError> {
        let status = SecItemDelete(identity(login) as CFDictionary)
        if status == errSecItemNotFound, login.scheme == "https", login.port == nil {
            var legacyIdentity: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: login.host,
                kSecAttrAccount as String: login.username,
                kSecAttrLabel as String: label,
            ]
            let legacyStatus = SecItemDelete(legacyIdentity as CFDictionary)
            guard legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound else {
                return .failure(.keychain(legacyStatus))
            }
        } else if status != errSecSuccess {
            return .failure(.keychain(status))
        }
        allCache = nil
        NotificationCenter.default.post(name: didChange, object: nil)
        return .success(())
    }

    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}
