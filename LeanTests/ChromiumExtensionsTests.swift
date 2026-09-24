import Foundation
import Testing
@testable import Lean

struct ChromiumExtensionsTests {
    private func makeExtension(at profile: URL, id: String, version: String, name: String, localeMessage: String? = nil) throws -> URL {
        let dir = profile.appendingPathComponent("Extensions/\(id)/\(version)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifestName: String
        if let message = localeMessage {
            manifestName = "__MSG_appName__"
            let locales = dir.appendingPathComponent("_locales/en", isDirectory: true)
            try FileManager.default.createDirectory(at: locales, withIntermediateDirectories: true)
            let messages = #"{"appName": {"message": "\#(message)"}}"#
            try Data(messages.utf8).write(to: locales.appendingPathComponent("messages.json"))
        } else {
            manifestName = name
        }
        let manifest = #"{"name": "\#(manifestName)", "version": "\#(version)", "manifest_version": 3}"#
        try Data(manifest.utf8).write(to: dir.appendingPathComponent("manifest.json"))
        return dir
    }

    @Test("Extension scan finds ids, resolves names, picks newest")
    func scansProfiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = root.appendingPathComponent("Default", isDirectory: true)
        let id1 = String(repeating: "a", count: 32)
        try makeExtension(at: profile, id: id1, version: "1.0", name: "Old")
        try makeExtension(at: profile, id: id1, version: "2.0", name: "New")
        let id2 = String(repeating: "b", count: 32)
        try makeExtension(at: profile, id: id2, version: "1.0", name: "", localeMessage: "Localized Name")
        // Junk the scan must ignore.
        try FileManager.default.createDirectory(at: profile.appendingPathComponent("Extensions/not-an-id", isDirectory: true), withIntermediateDirectories: true)
        let id3 = String(repeating: "c", count: 32)
        try FileManager.default.createDirectory(at: profile.appendingPathComponent("Extensions/\(id3)/9.9", isDirectory: true), withIntermediateDirectories: true)

        let found = ChromiumExtensions.scan(in: root)
        #expect(found.count == 2)
        let first = found.first { $0.id == id1 }
        #expect(first?.version == "2.0")
        #expect(first?.name == "New")
        #expect(first?.path.lastPathComponent == "2.0")
        #expect(found.first { $0.id == id2 }?.name == "Localized Name")
    }

    @Test("Version compare orders dotted numerics")
    func comparesVersions() {
        #expect(ChromiumExtensions.compareVersions("2.0", "1.9") == .orderedDescending)
        #expect(ChromiumExtensions.compareVersions("1.0", "1.0") == .orderedSame)
        #expect(ChromiumExtensions.compareVersions("7.0.6_0", "7.0.6") == .orderedDescending)
    }

    @Test("Empty folders scan to nothing")
    func scansEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ChromiumExtensions.scan(in: root).isEmpty)
    }
}
