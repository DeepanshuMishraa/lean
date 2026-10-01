import Foundation
import Testing
@testable import Lean

struct AddressResolverFileTests {
    private func makeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lean-\(UUID().uuidString).html")
        try "<h1>hi</h1>".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("An existing absolute path opens as a file")
    func absolutePath() throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let resolved = AddressResolver.resolve(file.path)
        #expect(resolved?.isFileURL == true)
        #expect(resolved?.lastPathComponent == file.lastPathComponent)
    }

    @Test("An explicit file URL stays a file URL")
    func explicitFileURL() {
        let resolved = AddressResolver.resolve("file:///tmp/index.html")
        #expect(resolved?.isFileURL == true)
    }

    @Test("A path that does not exist falls through to search")
    func missingPath() {
        let resolved = AddressResolver.resolve("/definitely/not/here.html")
        #expect(resolved?.host == "www.google.com")
    }

    @Test("A directory is not a page")
    func directory() {
        #expect(AddressResolver.fileURL(from: NSTemporaryDirectory()) == nil)
    }
}
