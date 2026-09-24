import Foundation
import Testing
import WebKit
@testable import Lean

struct NativeMessagingDelegateTests {
    @Test("native messaging delegate methods are wired to the controller")
    @MainActor
    func delegateWiring() {
        guard #available(macOS 15.4, *) else { return }
        let manager = BrowserExtensionManager.shared
        #expect(manager.responds(to: Selector(
            "webExtensionController:sendMessage:toApplicationWithIdentifier:forExtensionContext:replyHandler:")))
        #expect(manager.responds(to: Selector(
            "webExtensionController:connectUsingMessagePort:forExtensionContext:completionHandler:")))
    }
}

struct NativeHostManifestTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writeManifest(in folder: URL, name: String, program: String, origins: [String]) throws {
        let manifest: [String: Any] = [
            "name": name,
            "description": "test host",
            "path": program,
            "type": "stdio",
            "allowed_origins": origins,
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: folder.appendingPathComponent(name + ".json"))
    }

    @Test("a registered host that allows the origin resolves")
    func resolves() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeManifest(in: folder, name: "com.example.host", program: "/bin/echo",
                          origins: ["chrome-extension://abcdef/"])
        let program = try NativeHostManifests.resolveHost(
            named: "com.example.host", origin: "chrome-extension://abcdef/", folders: [folder])
        #expect(program.path == "/bin/echo")
    }

    @Test("an origin the manifest doesn't list is forbidden")
    func forbiddenOrigin() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeManifest(in: folder, name: "com.example.host", program: "/bin/echo",
                          origins: ["chrome-extension://abcdef/"])
        #expect(throws: NativeMessagingError.self) {
            try NativeHostManifests.resolveHost(
                named: "com.example.host", origin: "chrome-extension://other/", folders: [folder])
        }
    }

    @Test("a missing manifest is not found")
    func missing() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: NativeMessagingError.self) {
            try NativeHostManifests.resolveHost(
                named: "com.example.nope", origin: "chrome-extension://abcdef/", folders: [folder])
        }
    }

    @Test("a hostile host name never touches the disk as a path")
    func invalidName() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["../evil", "com.example;rm", "", "COM.EXAMPLE.HOST"] {
            #expect(throws: NativeMessagingError.self) {
                try NativeHostManifests.resolveHost(
                    named: name, origin: "chrome-extension://abcdef/", folders: [folder])
            }
        }
    }

    @Test("a relative program resolves against its folder and must be executable")
    func relativePath() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("host.sh")
        try "#!/bin/sh\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try writeManifest(in: folder, name: "com.example.host", program: "host.sh",
                          origins: ["chrome-extension://abcdef/"])
        let program = try NativeHostManifests.resolveHost(
            named: "com.example.host", origin: "chrome-extension://abcdef/", folders: [folder])
        #expect(program.path == script.path)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: script.path)
        #expect(throws: NativeMessagingError.self) {
            try NativeHostManifests.resolveHost(
                named: "com.example.host", origin: "chrome-extension://abcdef/", folders: [folder])
        }
    }
}

struct NativeMessageFramingTests {
    @Test("a frame round-trips through the decoder")
    func roundTrip() throws {
        let json = Data(#"{"hello":"world"}"#.utf8)
        var decoder = NativeMessageFraming.Decoder()
        let bodies = decoder.append(try NativeMessageFraming.encode(json: json))
        #expect(bodies == [json])
    }

    @Test("split chunks reassemble and back-to-back frames separate")
    func chunking() throws {
        let first = Data(#"{"a":1}"#.utf8)
        let second = Data(#"{"b":2}"#.utf8)
        let stream = try NativeMessageFraming.encode(json: first) + NativeMessageFraming.encode(json: second)
        var decoder = NativeMessageFraming.Decoder()
        var bodies: [Data] = []
        for at in stride(from: 0, to: stream.count, by: 3) {
            bodies += decoder.append(stream.subdata(in: at..<min(at + 3, stream.count)))
        }
        #expect(bodies == [first, second])
    }

    @Test("an overlong message is refused before touching the pipe")
    func tooLong() {
        let json = Data(repeating: 0x20, count: NativeMessageFraming.maxMessageBytes + 1)
        #expect(throws: NativeMessagingError.self) {
            try NativeMessageFraming.encode(json: json)
        }
    }

    @Test("an absurd length poisons the stream instead of allocating")
    func poisoned() throws {
        var decoder = NativeMessageFraming.Decoder()
        var length = UInt32(NativeMessageFraming.maxMessageBytes + 1).littleEndian
        let bodies = decoder.append(Data(bytes: &length, count: 4))
        #expect(bodies.isEmpty)
        #expect(decoder.poisoned)
        #expect(decoder.append(Data([1, 2, 3])).isEmpty)
    }

    @Test("framing survives a real pipe round-trip")
    func livePipe() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        defer {
            process.terminate()
        }
        let json = Data(#"{"ping":"pair"}"#.utf8)
        try input.fileHandleForWriting.write(contentsOf: NativeMessageFraming.encode(json: json))
        var decoder = NativeMessageFraming.Decoder()
        let deadline = Date().addingTimeInterval(5)
        var bodies: [Data] = []
        while bodies.isEmpty, Date() < deadline {
            let chunk = output.fileHandleForReading.availableData
            if !chunk.isEmpty {
                bodies = decoder.append(chunk)
            } else {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        #expect(bodies == [json])
    }
}
