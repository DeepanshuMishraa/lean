import Foundation
import Testing

/// The service's session and runner flow, against real processes.
/// A tiny echo host stands in for one: like a real host it ignores its
/// origin argument and copies stdin to stdout, so a framed write must come
/// back as the same framed message. (`/bin/cat` won't do: it reads its
/// origin argument as a filename and exits.)
struct HostSessionTests {
    static func makeEchoHost() throws -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("lean-echo-host-\(UUID().uuidString).sh")
        try "#!/bin/sh\nexec /bin/cat\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    @Test("a written message echoes back framed")
    func echo() async throws {
        let session = HostSession(program: try Self.makeEchoHost(), origin: "chrome-extension://test/")
        try session.start()
        defer { session.stop() }
        let json = Data(#"{"hello":"helper"}"#.utf8)
        try session.write(json: json)
        let answer = try await withCheckedThrowingContinuation { continuation in
            session.readOne(timeout: 5) { result in
                continuation.resume(with: result.map { $0 ?? Data() })
            }
        }
        #expect(answer == json)
    }

    @Test("reading with a silent host times out instead of hanging")
    func readTimeout() async throws {
        let session = HostSession(program: try Self.makeEchoHost(), origin: "chrome-extension://test/")
        try session.start()
        defer { session.stop() }
        await #expect(throws: NativeMessagingError.self) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                session.readOne(timeout: 0.2) { result in
                    continuation.resume(with: result)
                }
            }
        }
    }

    @Test("an overlong write is refused before touching the pipe")
    func writeTooLong() throws {
        let session = HostSession(program: try HostSessionTests.makeEchoHost(), origin: "chrome-extension://test/")
        #expect(throws: NativeMessagingError.self) {
            try session.write(json: Data(repeating: 0x20, count: NativeMessageFraming.maxMessageBytes + 1))
        }
    }
}

struct NativeHostRunnerTests {
    private func manifestFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let host = try HostSessionTests.makeEchoHost()
        let manifest: [String: Any] = [
            "name": "com.example.host",
            "description": "test host",
            "path": host.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://abcdef/"],
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: folder.appendingPathComponent("com.example.host.json"))
        return folder
    }

    @Test("one-shot send returns the host's first answer")
    func oneShot() async throws {
        let runner = NativeHostRunner()
        runner.manifestFolders = [try manifestFolder()]
        let json = Data(#"{"pair":"first-code"}"#.utf8)
        let answer: Data? = try await withCheckedThrowingContinuation { continuation in
            runner.sendOneShotMessage(json, toHostNamed: "com.example.host", origin: "chrome-extension://abcdef/") { data, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: data) }
            }
        }
        #expect(answer == json)
    }

    @Test("one-shot to a forbidden origin is refused without launching")
    func oneShotForbidden() async {
        let runner = NativeHostRunner()
        runner.manifestFolders = [try! manifestFolder()]
        let json = Data(#"{}"#.utf8)
        await #expect(throws: Error.self) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                runner.sendOneShotMessage(json, toHostNamed: "com.example.host", origin: "chrome-extension://intruder/") { data, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: data) }
                }
            }
        }
    }

    @Test("a launched session posts and closes")
    func launchPostClose() async throws {
        let runner = NativeHostRunner()
        runner.manifestFolders = [try manifestFolder()]
        let sessionID: String = try await withCheckedThrowingContinuation { continuation in
            runner.launchHost(named: "com.example.host", origin: "chrome-extension://abcdef/") { id, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: id!) }
            }
        }
        let json = Data(#"{"stay":"paired"}"#.utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            runner.postMessage(json, toSession: sessionID) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Never>) in
            runner.closeSession(sessionID) { _ in continuation.resume() }
        }
    }
}
