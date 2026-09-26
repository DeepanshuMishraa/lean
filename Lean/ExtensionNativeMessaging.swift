import Foundation
import WebKit

// Chrome-style native messaging for Lean's extensions, over the
// LeanNativeHosts XPC service: `runtime.sendNativeMessage` runs a host
// once and takes its first answer; `runtime.connectNative` keeps a host
// running on a port until either end lets go. This is what pairs iCloud
// Passwords with Apple's helper on the first code and keeps it paired,
// and what lets 1Password and Bitwarden talk to their desktop apps.
//
// The app itself never launches anything: it names a registered host and
// an origin, and the unsandboxed service resolves the manifest, checks the
// origin is allowed, and spawns the program (see NativeMessagingCore and
// LeanNativeHosts). A host that lists the extension's id among its allowed
// origins runs; any other is refused, here and there.

@available(macOS 15.4, *)
@MainActor
final class NativeMessagingClient {
    static let shared = NativeMessagingClient()

    private static let serviceName = "com.dipxsy.lean.LeanNativeHosts"
    private var connection: NSXPCConnection?
    private let callbacks = NativeClientCallbacks()
    /// Failers for calls still awaiting an XPC reply, run when the service
    /// connection dies so no Task hangs past it.
    private var pending: [UUID: (Error) -> Void] = [:]

    private func proxy() throws -> LeanNativeHostServiceProtocol {
        if let connection {
            if let proxy = connection.remoteObjectProxy as? LeanNativeHostServiceProtocol {
                return proxy
            }
            self.connection = nil
        }
        let connection = NSXPCConnection(serviceName: Self.serviceName)
        connection.exportedInterface = NSXPCInterface(with: LeanNativeHostClientProtocol.self)
        connection.exportedObject = callbacks
        connection.remoteObjectInterface = NSXPCInterface(with: LeanNativeHostServiceProtocol.self)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor [weak self] in self?.connectionDied() }
        }
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor [weak self] in self?.connectionDied() }
        }
        connection.resume()
        self.connection = connection
        guard let proxy = connection.remoteObjectProxy as? LeanNativeHostServiceProtocol else {
            self.connection = nil
            throw NativeMessagingError.hostExited
        }
        return proxy
    }

    private func connectionDied() {
        connection = nil
        let failers = pending
        pending = [:]
        failers.values.forEach { $0(NativeMessagingError.hostExited) }
        NativePortStore.disconnectAll()
    }

    /// An XPC reply with a timeout: a hung or dead service must never hang
    /// the extension (or the browser) past it. XPC replies arrive off the
    /// main actor, so every path back hops onto it.
    private func call<T>(timeout: TimeInterval, _ body: @escaping (@escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let state = TimeoutState()
            func finish(_ result: Result<T, Error>) {
                Task { @MainActor in
                    guard state.claim() else { return }
                    self.pending.removeValue(forKey: id)
                    continuation.resume(with: result)
                }
            }
            pending[id] = { finish(.failure($0)) }
            body { finish($0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(NativeMessagingError.hostExited))
            }
        }
    }

    func launch(host name: String, origin: String) async throws -> String {
        let proxy = try proxy()
        let id: String? = try await call(timeout: 15) { finish in
            proxy.launchHost(named: name, origin: origin) { sessionID, error in
                if let error { finish(.failure(error)) } else { finish(.success(sessionID)) }
            }
        }
        guard let id else { throw NativeMessagingError.hostExited }
        return id
    }

    func post(json: Data, to sessionID: String) async throws {
        let proxy = try proxy()
        try await call(timeout: 15) { (finish: @escaping (Result<Void, Error>) -> Void) in
            proxy.postMessage(json, toSession: sessionID) { error in
                if let error { finish(.failure(error)) } else { finish(.success(())) }
            }
        }
    }

    func sendOneShot(json: Data, host name: String, origin: String) async throws -> Data? {
        let proxy = try proxy()
        return try await call(timeout: 45) { finish in
            proxy.sendOneShotMessage(json, toHostNamed: name, origin: origin) { data, error in
                if let error { finish(.failure(error)) } else { finish(.success(data)) }
            }
        }
    }

    func close(session sessionID: String) {
        guard let connection,
              let proxy = connection.remoteObjectProxy as? LeanNativeHostServiceProtocol else { return }
        proxy.closeSession(sessionID) { _ in }
    }
}

/// First claimant wins; everyone else stands down.
private final class TimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

/// Callbacks from the service: XPC delivers them off the main actor, so
/// each hops over before touching ports.
@available(macOS 15.4, *)
private final class NativeClientCallbacks: NSObject, LeanNativeHostClientProtocol {
    func nativeHostSession(_ sessionID: String, didReceiveMessageData json: Data) {
        Task { @MainActor in
            guard let record = NativePortStore.port(for: sessionID),
                  let message = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]) else { return }
            record.port.sendMessage(message, completionHandler: nil)
        }
    }

    func nativeHostSessionDidExit(_ sessionID: String) {
        Task { @MainActor in
            guard let record = NativePortStore.remove(session: sessionID) else { return }
            if !record.port.isDisconnected { record.port.disconnect() }
        }
    }
}

/// Live extension ports with a host behind them, by XPC session.
@available(macOS 15.4, *)
@MainActor
enum NativePortStore {
    struct Record {
        let port: WKWebExtension.MessagePort
    }

    private static var ports: [String: Record] = [:]

    static func add(port: WKWebExtension.MessagePort, session sessionID: String) {
        ports[sessionID] = Record(port: port)
    }

    static func port(for sessionID: String) -> Record? { ports[sessionID] }

    @discardableResult
    static func remove(session sessionID: String) -> Record? {
        ports.removeValue(forKey: sessionID)
    }

    /// The service going away orphans every helper: the extensions hear
    /// their ports disconnect, as if each host had exited.
    static func disconnectAll() {
        let live = ports
        ports = [:]
        live.values.forEach { if !$0.port.isDisconnected { $0.port.disconnect() } }
    }
}

@available(macOS 15.4, *)
extension BrowserExtensionManager {
    private func nativeOrigin(_ context: WKWebExtensionContext) -> String {
        "chrome-extension://\(context.uniqueIdentifier)/"
    }

    /// The extension must have asked for native messaging and been granted
    /// it, or the host never hears from it.
    private func checkNativePermission(_ context: WKWebExtensionContext) throws {
        let key = WKWebExtension.Permission.nativeMessaging.rawValue
        guard let record = installed.first(where: { $0.id == context.uniqueIdentifier }),
              record.grantedPermissions.contains(key) else {
            throw NativeMessagingError.forbidden
        }
    }

    /// `runtime.sendNativeMessage`: run the host, send one, take its first
    /// answer, stop it.
    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext
    ) async throws -> Any? {
        guard let applicationIdentifier, !applicationIdentifier.isEmpty else {
            throw NativeMessagingError.notFound
        }
        try checkNativePermission(extensionContext)
        let json = try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed])
        let answer = try await NativeMessagingClient.shared.sendOneShot(
            json: json, host: applicationIdentifier, origin: nativeOrigin(extensionContext))
        guard let answer else { return nil }
        return try JSONSerialization.jsonObject(with: answer, options: [.fragmentsAllowed])
    }

    /// `runtime.connectNative`: run the host and keep the two talking until
    /// either end lets go.
    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let applicationIdentifier = port.applicationIdentifier, !applicationIdentifier.isEmpty else {
            completionHandler(NativeMessagingError.notFound)
            return
        }
        do {
            try checkNativePermission(extensionContext)
        } catch {
            completionHandler(error)
            return
        }
        let origin = nativeOrigin(extensionContext)
        Task {
            do {
                let sessionID = try await NativeMessagingClient.shared.launch(host: applicationIdentifier, origin: origin)
                NativePortStore.add(port: port, session: sessionID)
                port.messageHandler = { message, _ in
                    Task { @MainActor in
                        guard let message,
                              let json = try? JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed]) else { return }
                        do {
                            try await NativeMessagingClient.shared.post(json: json, to: sessionID)
                        } catch {
                            if let record = NativePortStore.remove(session: sessionID),
                               !record.port.isDisconnected {
                                record.port.disconnect()
                            }
                        }
                    }
                }
                port.disconnectHandler = { _ in
                    Task { @MainActor in
                        NativePortStore.remove(session: sessionID)
                        NativeMessagingClient.shared.close(session: sessionID)
                    }
                }
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
}
