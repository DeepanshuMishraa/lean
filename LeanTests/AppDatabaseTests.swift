import Foundation
import Testing
@testable import Lean

struct AppDatabaseTests {
    @Test("SQLite state survives reopening and overwrites atomically")
    func roundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Lean.sqlite3")

        do {
            let database = try AppDatabase(url: url)
            _ = try database.set("Dark", forKey: "theme").get()
            _ = try database.set(["https://example.com"], forKey: "session").get()
            _ = try database.set("Light", forKey: "theme").get()
        }

        let reopened = try AppDatabase(url: url)
        #expect(try reopened.value(String.self, forKey: "theme").get() == "Light")
        #expect(try reopened.value([String].self, forKey: "session").get() == ["https://example.com"])
        #expect(try reopened.value(Bool.self, forKey: "missing").get() == nil)
    }
}
