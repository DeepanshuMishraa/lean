import Foundation

// Chrome-style native messaging, shared by the Lean app and the
// LeanNativeHosts XPC service (which is where hosts actually run — the
// sandboxed app cannot spawn them itself).
//
// Hosts register with a browser by leaving a small JSON manifest in a
// NativeMessagingHosts folder: a name, the program to run, and which
// extensions may run it. Lean reads the same manifests the Chromium
// browsers read, runs the same program with the same origin argument, and
// speaks the same framing — each message a four-byte little-endian length
// and a line of JSON over stdin/stdout. A host that lists the extension's
// origin among its allowed origins is run; any other is refused. Some hosts
// also check which browser is calling and may refuse one they don't know;
// that is theirs to decide.

enum NativeMessagingError: LocalizedError {
    case forbidden
    case notFound
    case hostExited
    case messageTooLong
    case messageInvalid

    var errorDescription: String? {
        switch self {
        case .forbidden: return "Access to the specified native messaging host is forbidden."
        case .notFound: return "Specified native messaging host not found."
        case .hostExited: return "Native messaging host has exited."
        case .messageTooLong: return "Message too long for a native messaging host."
        case .messageInvalid: return "Native messaging host message is not JSON."
        }
    }

    var nsError: NSError {
        NSError(domain: "com.dipxsy.lean.NativeMessaging", code: code, userInfo: [NSLocalizedDescriptionKey: errorDescription ?? "Native messaging failed."])
    }

    private var code: Int {
        switch self {
        case .forbidden: return 1
        case .notFound: return 2
        case .hostExited: return 3
        case .messageTooLong: return 4
        case .messageInvalid: return 5
        }
    }
}

enum NativeHostManifests {
    /// Where Chromium browsers look for host manifests, per user and for
    /// the whole Mac. Lean reads the same folders: a host that supports
    /// Chrome, Edge, Brave or Arc supports Lean without re-registering.
    /// Read by the unsandboxed XPC service — the sandboxed app cannot see
    /// outside its container.
    static func searchFolders() -> [URL] {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return [
            support.appendingPathComponent("Google/Chrome/NativeMessagingHosts"),
            support.appendingPathComponent("Chromium/NativeMessagingHosts"),
            support.appendingPathComponent("Microsoft Edge/NativeMessagingHosts"),
            support.appendingPathComponent("BraveSoftware/Brave-Browser/NativeMessagingHosts"),
            support.appendingPathComponent("Arc/User Data/NativeMessagingHosts"),
            URL(fileURLWithPath: "/Library/Google/Chrome/NativeMessagingHosts"),
            URL(fileURLWithPath: "/Library/Application Support/Chromium/NativeMessagingHosts"),
            URL(fileURLWithPath: "/Library/Microsoft/Edge/NativeMessagingHosts"),
        ]
    }

    /// The program for `name`, if one is registered and lets `origin`
    /// (usually `chrome-extension://<id>/`) in.
    static func resolveHost(named name: String, origin: String, folders: [URL]? = nil) throws -> URL {
        guard name.range(of: #"^[a-z0-9_]+(\.[a-z0-9_]+)*$"#, options: .regularExpression) != nil else {
            throw NativeMessagingError.forbidden
        }
        for folder in folders ?? searchFolders() {
            let file = folder.appendingPathComponent(name + ".json")
            guard let data = try? Data(contentsOf: file),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let path = manifest["path"] as? String
            else { continue }
            let allowed = manifest["allowed_origins"] as? [String] ?? []
            guard allowed.contains(origin) else {
                throw NativeMessagingError.forbidden
            }
            let program = path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path)
            guard FileManager.default.isExecutableFile(atPath: program.path) else {
                throw NativeMessagingError.notFound
            }
            return program
        }
        throw NativeMessagingError.notFound
    }
}

enum NativeMessageFraming {
    /// Chrome's limit for a single message to a host.
    static let maxMessageBytes = 1 << 20

    /// A JSON body with Chrome's four-byte little-endian length prefix.
    static func encode(json: Data) throws -> Data {
        guard json.count <= maxMessageBytes else { throw NativeMessagingError.messageTooLong }
        var length = UInt32(json.count).littleEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(json)
        return frame
    }

    /// Incremental parser for a host's stdout: feed chunks, get back each
    /// complete JSON body. An absurd length resets the stream — resyncing
    /// mid-pipe is impossible, and Chrome drops such hosts.
    struct Decoder {
        private var buffer = Data()
        private(set) var poisoned = false

        mutating func append(_ chunk: Data) -> [Data] {
            if poisoned { return [] }
            buffer.append(chunk)
            var bodies: [Data] = []
            while buffer.count >= 4 {
                let length = Int(buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
                guard length <= NativeMessageFraming.maxMessageBytes else {
                    buffer.removeAll()
                    poisoned = true
                    return bodies
                }
                guard buffer.count >= 4 + length else { break }
                bodies.append(buffer.subdata(in: 4..<(4 + length)))
                buffer.removeSubrange(0..<(4 + length))
            }
            return bodies
        }
    }
}

// MARK: - XPC protocols (app ↔ LeanNativeHosts service)

@objc(LeanNativeHostServiceProtocol)
protocol LeanNativeHostServiceProtocol {
    /// Launch `name` for `origin`; replies the session id.
    func launchHost(named name: String, origin: String, reply: @escaping (String?, NSError?) -> Void)
    /// Post one framed message to a live session.
    func postMessage(_ json: Data, toSession sessionID: String, reply: @escaping (NSError?) -> Void)
    /// `runtime.sendNativeMessage`: launch, send one, take the first answer, stop.
    func sendOneShotMessage(_ json: Data, toHostNamed name: String, origin: String, reply: @escaping (Data?, NSError?) -> Void)
    /// Stop the host behind a session.
    func closeSession(_ sessionID: String, reply: @escaping (NSError?) -> Void)
}

@objc(LeanNativeHostClientProtocol)
protocol LeanNativeHostClientProtocol {
    func nativeHostSession(_ sessionID: String, didReceiveMessageData json: Data)
    func nativeHostSessionDidExit(_ sessionID: String)
}
