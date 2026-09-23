import Foundation
import LocalAuthentication
import Security

struct SavedPassword: Identifiable, Hashable {
    let scheme: String
    let host: String
    let port: Int?
    let username: String
    let createdAt: Date?

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

    static func normalizedHost(_ host: String) -> String? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty,
              host.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\@:%?#")) == nil,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: "https://\(host)"),
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: label,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return .success([]) }
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
            return SavedPassword(
                scheme: scheme,
                host: host,
                port: port,
                username: username,
                createdAt: item[kSecAttrCreationDate as String] as? Date
            )
        }
        return .success(logins.sorted { ($0.origin, $0.username) < ($1.origin, $1.username) })
    }

    static func matchesOrigin(_ login: SavedPassword, _ origin: URL) -> Bool {
        guard let normalized = normalizedOrigin(origin) else { return false }
        return login.scheme == normalized.scheme && login.host == normalized.host && login.port == normalized.port
    }

    static func forOrigin(_ origin: URL) -> Result<[SavedPassword], VaultError> {
        guard normalizedOrigin(origin) != nil else { return .failure(.invalidOrigin) }
        return all().map { $0.filter { matchesOrigin($0, origin) } }
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
        let identity = identity(login)
        var add = identity
        add[kSecValueData as String] = Data(password.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        add[kSecAttrComment as String] = label
        let update: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrComment as String: label,
        ]
        let status = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
        let result: OSStatus
        if status == errSecItemNotFound {
            if login.scheme == "https", login.port == nil {
                // Phase 1 imports omitted scheme and port; only default HTTPS can match them safely.
                let legacyIdentity: [String: Any] = [
                    kSecClass as String: kSecClassInternetPassword,
                    kSecAttrServer as String: login.host,
                    kSecAttrAccount as String: username,
                    kSecAttrLabel as String: label,
                ]
                let legacyStatus = SecItemUpdate(legacyIdentity as CFDictionary, update as CFDictionary)
                result = legacyStatus == errSecItemNotFound ? SecItemAdd(add as CFDictionary, nil) : legacyStatus
            } else {
                result = SecItemAdd(add as CFDictionary, nil)
            }
        } else {
            result = status
        }
        guard result == errSecSuccess else { return .failure(.keychain(result)) }
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
            if let port = login.port { legacyQuery[kSecAttrPort as String] = port }
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
            if let port = login.port { legacyIdentity[kSecAttrPort as String] = port }
            let legacyStatus = SecItemDelete(legacyIdentity as CFDictionary)
            guard legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound else {
                return .failure(.keychain(legacyStatus))
            }
        } else if status != errSecSuccess {
            return .failure(.keychain(status))
        }
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
