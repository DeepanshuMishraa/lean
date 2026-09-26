import Foundation

// LeanNativeHosts: the unsandboxed XPC service that runs native messaging
// hosts for Lean's extensions — iCloud Passwords' helper, 1Password's
// desktop bridge, and the like. The Lean app itself is sandboxed and the
// kernel refuses its spawns, so launching happens here instead.
//
// Trust boundary: only programs named by a manifest found in the fixed
// NativeMessagingHosts folders are ever launched, and only for an origin
// that manifest allows. That is the same trust Chrome places in those
// files. The service never launches an arbitrary path the app names.

final class NativeHostRunner: NSObject, LeanNativeHostServiceProtocol {
    weak var connection: NSXPCConnection?
    private var sessions: [String: HostSession] = [:]
    private let lock = NSLock()
    /// Manifest folders to search instead of the browsers' own. Set in
    /// tests; nil in the service, which reads the real folders.
    var manifestFolders: [URL]?

    private var client: LeanNativeHostClientProtocol? {
        connection?.remoteObjectProxy as? LeanNativeHostClientProtocol
    }

    func launchHost(named name: String, origin: String, reply: @escaping (String?, NSError?) -> Void) {
        let program: URL
        do {
            program = try NativeHostManifests.resolveHost(named: name, origin: origin, folders: manifestFolders)
        } catch {
            reply(nil, error as NSError)
            return
        }
        // Registered before start(): output or an exit arriving between
        // spawn and handler assignment would otherwise be dropped, and a
        // start failure must not leave the session listed.
        let session = HostSession(program: program, origin: origin)
        lock.lock()
        sessions[session.id] = session
        lock.unlock()
        session.onMessage = { [weak self] json in
            self?.client?.nativeHostSession(session.id, didReceiveMessageData: json)
        }
        session.onExit = { [weak self] in
            self?.forget(session.id)
            self?.client?.nativeHostSessionDidExit(session.id)
        }
        do {
            try session.start()
        } catch {
            forget(session.id)
            reply(nil, error as NSError)
            return
        }
        // A new launch is often a worker starting over; a previous session
        // that already exited may still be listed.
        stopOrphans(except: session.id)
        reply(session.id, nil)
    }

    func postMessage(_ json: Data, toSession sessionID: String, reply: @escaping (NSError?) -> Void) {
        guard let session = lockedSession(sessionID) else {
            reply(NativeMessagingError.hostExited.nsError)
            return
        }
        do {
            try session.write(json: json)
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func sendOneShotMessage(_ json: Data, toHostNamed name: String, origin: String, reply: @escaping (Data?, NSError?) -> Void) {
        let program: URL
        do {
            program = try NativeHostManifests.resolveHost(named: name, origin: origin, folders: manifestFolders)
        } catch {
            reply(nil, error as NSError)
            return
        }
        let session = HostSession(program: program, origin: origin)
        do {
            try session.start()
        } catch {
            reply(nil, error as NSError)
            return
        }
        // Waiter before write: a fast host answers between the two, and an
        // answer with no waiter is dropped to onMessage (nil here) — lost.
        session.readOne(timeout: 30) { answer in
            session.stop()
            switch answer {
            case .success(let data): reply(data, nil)
            case .failure(let error): reply(nil, error as NSError)
            }
        }
        do {
            try session.write(json: json)
        } catch {
            // The waiter above is still pending: stop() would resume it with
            // success(nil) and reply success. Drop it first so the write
            // error is what the caller hears, exactly once.
            session.dropWaiters()
            session.stop()
            reply(nil, error as NSError)
            return
        }
    }

    func closeSession(_ sessionID: String, reply: @escaping (NSError?) -> Void) {
        forget(sessionID)?.stop()
        reply(nil)
    }

    /// Called when the app's connection goes away: no client will ever read
    /// from these helpers again, so stop them instead of leaving Apple's
    /// code prompt (or any other host UI) open behind the browser.
    func connectionGone() {
        lock.lock()
        let live = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        live.forEach { $0.stop() }
    }

    private func lockedSession(_ id: String) -> HostSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[id]
    }

    @discardableResult
    private func forget(_ id: String) -> HostSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions.removeValue(forKey: id)
    }

    private func stopOrphans(except id: String) {
        lock.lock()
        let orphans = sessions.values.filter { $0.id != id && $0.exited }
        orphans.forEach { sessions[$0.id] = nil }
        lock.unlock()
        orphans.forEach { $0.stop() }
    }
}

/// One host program and Chrome's stdio framing around it.
final class HostSession {
    let id = UUID().uuidString
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var decoder = NativeMessageFraming.Decoder()
    private let lock = NSLock()
    private var waiters: [Waiter] = []
    private(set) var exited = false
    /// The process is gone but stdout may not be: set by terminationHandler,
    /// which leaves finishing to the EOF path (or its delay fallback).
    private(set) var processExited = false
    var onMessage: ((Data) -> Void)?
    var onExit: (() -> Void)?

    init(program: URL, origin: String) {
        process.executableURL = program
        process.arguments = [origin]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // A host that is already gone — refused to run, killed as it
        // started — must not take the service down with SIGPIPE when its
        // closed pipe is written: refused, the write only fails.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self.finish()
                return
            }
            self.take(chunk)
        }
        // A reply already sitting in the pipe must reach its waiter through
        // the EOF path's take() — never finish here, which would resume
        // waiters with nil and report the exit before the answer. The exit
        // is recorded; if EOF never arrives (an inherited fd held open),
        // finish on a delay instead of hanging the session.
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.processExited = true
            self.lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.finish()
            }
        }
        try process.run()
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        finish()
    }

    func write(json: Data) throws {
        try input.fileHandleForWriting.write(contentsOf: NativeMessageFraming.encode(json: json))
    }

    /// Abandons pending waiters without resuming them: the caller's own
    /// error (e.g. a failed write) is the answer, and the timeout work
    /// standing down on the missing waiter keeps delivery exactly-once.
    func dropWaiters() {
        lock.lock()
        waiters = []
        lock.unlock()
    }

    /// The next message from the host, or nil if it exits first. Gives up
    /// after `timeout` seconds so an XPC reply never hangs forever.
    func readOne(timeout: TimeInterval, completion: @escaping (Result<Data?, Error>) -> Void) {
        let waiter = Waiter(resume: completion)
        lock.lock()
        waiters.append(waiter)
        lock.unlock()
        let work = DispatchWorkItem { [weak self, waiter] in
            guard let self else { return }
            self.lock.lock()
            if let index = self.waiters.firstIndex(where: { $0.id == waiter.id }) {
                let waiter = self.waiters.remove(at: index)
                self.lock.unlock()
                waiter.resume(throwing: NativeMessagingError.hostExited)
            } else {
                self.lock.unlock()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private func take(_ chunk: Data) {
        let bodies = decoder.append(chunk)
        guard !bodies.isEmpty else { return }
        lock.lock()
        var pairs: [(Waiter, Data)] = []
        var leftover = bodies
        while !leftover.isEmpty, !waiters.isEmpty {
            pairs.append((waiters.removeFirst(), leftover.removeFirst()))
        }
        lock.unlock()
        // Only the first resume per waiter wins — a timeout firing at the
        // same moment stands down, so `completion` runs exactly once.
        var stillHungry: [Data] = []
        for (waiter, body) in pairs {
            if waiter.resume(returning: body) { continue }
            stillHungry.append(body)
        }
        (stillHungry + leftover).forEach { onMessage?($0) }
    }

    private func finish() {
        lock.lock()
        let pending = waiters
        waiters = []
        let wasExited = exited
        exited = true
        lock.unlock()
        guard !wasExited else { return }
        pending.forEach { $0.resume(returning: nil) }
        onExit?()
        onExit = nil
    }
}

// MARK: - one-shot waiter bookkeeping

/// First claimant wins; everyone else stands down. Guards the race between
/// a message arriving and the timeout firing.
private final class TimeoutState: @unchecked Sendable {
    let id = UUID()
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

private struct Waiter {
    let id = UUID()
    private let state = TimeoutState()
    private let resumeImpl: (Result<Data?, Error>) -> Void

    init(resume: @escaping (Result<Data?, Error>) -> Void) {
        self.resumeImpl = resume
    }

    /// Resumes unless the timeout already won. Returns whether this call won.
    @discardableResult
    func resume(returning value: Data?) -> Bool {
        guard state.claim() else { return false }
        resumeImpl(.success(value))
        return true
    }

    @discardableResult
    func resume(throwing error: Error) -> Bool {
        guard state.claim() else { return false }
        resumeImpl(.failure(error))
        return true
    }
}
