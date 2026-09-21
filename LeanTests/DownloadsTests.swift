import Foundation
import PhosphorSwift
import Testing
@testable import Lean

private func temporaryDownloadsDatabase() throws -> (AppDatabase, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (try AppDatabase(url: directory.appendingPathComponent("Lean.sqlite3")), directory)
}

struct DownloadsTests {
    @MainActor
    @Test("DownloadManager tracks progress and completion")
    func progressAndCompletion() {
        let manager = DownloadManager(database: nil)
        let dest = URL(fileURLWithPath: "/tmp/lean-test-file.zip")
        let id = manager.beginDownload(fileName: "lean-test-file.zip", sourceURL: URL(string: "https://example.com/f.zip"), destinationURL: dest, totalBytes: 1000)

        #expect(manager.hasActiveDownloads)
        manager.updateProgress(id: id, receivedBytes: 250, totalBytes: 1000, speedBytesPerSec: 500)
        #expect(manager.downloads.first?.fractionCompleted == 0.25)

        manager.finishDownload(id: id)
        #expect(!manager.hasActiveDownloads)
        #expect(manager.downloads.first?.state == .completed)
        #expect(manager.downloads.first?.endDate != nil)
    }

    @MainActor
    @Test("DownloadManager unique destination avoids collisions")
    func uniqueDestination() throws {
        let manager = DownloadManager(database: nil)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        manager.setDownloadDirectory(tempDir)

        let first = manager.uniqueDestination(for: "a.txt")
        #expect(first.lastPathComponent == "a.txt")

        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let second = manager.uniqueDestination(for: "a.txt")
        #expect(second.lastPathComponent == "a 1.txt")
    }

    @Test("DownloadFormat helpers")
    func formatting() {
        #expect(DownloadFormat.fileSize(0) == "Zero KB" || !DownloadFormat.fileSize(0).isEmpty)
        #expect(DownloadFormat.speed(0) == "—")
        #expect(!DownloadFormat.speed(1024).isEmpty)
        #expect(DownloadFormat.progressText(received: 50, total: 100).contains("50%"))
        #expect(DownloadFormat.systemImage(for: "movie.mp4") == "film.fill")
        #expect(DownloadFormat.systemImage(for: "unknown.xyz") == "doc.fill")
        #expect(DownloadFormat.icon(for: "movie.mp4") == .fileVideo)
        #expect(DownloadFormat.icon(for: "unknown.xyz") == .file)
    }

    @MainActor
    @Test("DownloadManager defaults to the user's Downloads folder")
    func defaultDirectory() {
        let manager = DownloadManager(database: nil)
        #expect(manager.downloadDirectory == DownloadManager.defaultDownloadsDirectory())
        #expect(manager.downloadDirectory.lastPathComponent == "Downloads")
    }

    @MainActor
    @Test("DownloadManager persists a custom download directory")
    func persistsCustomDirectory() throws {
        let (database, dir) = try temporaryDownloadsDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let custom = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: custom) }

        let manager = DownloadManager(database: database)
        manager.setDownloadDirectory(custom)
        #expect(manager.downloadDirectory.standardizedFileURL == custom.standardizedFileURL)

        let reloaded = DownloadManager(database: database)
        #expect(reloaded.downloadDirectory.standardizedFileURL == custom.standardizedFileURL)
    }

    @MainActor
    @Test("DownloadManager falls back to Downloads when the saved folder is gone")
    func missingSavedDirectoryFallsBack() throws {
        let (database, dir) = try temporaryDownloadsDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ghost = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        _ = database.set(ghost, forKey: "downloadsDirectory_v1")

        let manager = DownloadManager(database: database)
        #expect(manager.downloadDirectory == DownloadManager.defaultDownloadsDirectory())
    }
}
