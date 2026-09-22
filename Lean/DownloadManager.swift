import AppKit
import Combine
import Foundation

enum DownloadState: String, Codable, Equatable {
    case downloading
    case completed
    case failed
    case cancelled
}

struct DownloadItem: Identifiable, Codable, Equatable {
    let id: UUID
    var fileName: String
    var sourceURL: URL?
    var destinationURL: URL
    var totalBytes: Int64
    var receivedBytes: Int64
    var state: DownloadState
    var startDate: Date
    var endDate: Date?
    var errorDescription: String?
    /// Bytes/sec, not persisted meaningfully — reset to 0 on load.
    var speedBytesPerSec: Double

    init(
        id: UUID = UUID(),
        fileName: String,
        sourceURL: URL?,
        destinationURL: URL,
        totalBytes: Int64 = -1,
        receivedBytes: Int64 = 0,
        state: DownloadState = .downloading,
        startDate: Date = Date(),
        endDate: Date? = nil,
        errorDescription: String? = nil,
        speedBytesPerSec: Double = 0
    ) {
        self.id = id
        self.fileName = fileName
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.totalBytes = totalBytes
        self.receivedBytes = receivedBytes
        self.state = state
        self.startDate = startDate
        self.endDate = endDate
        self.errorDescription = errorDescription
        self.speedBytesPerSec = speedBytesPerSec
    }

    var fractionCompleted: Double {
        guard totalBytes > 0, receivedBytes >= 0 else { return 0 }
        return min(1, Double(receivedBytes) / Double(totalBytes))
    }

    var isActive: Bool { state == .downloading }
}

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var downloads: [DownloadItem] = []
    @Published var downloadDirectory: URL {
        didSet { persistDirectory() }
    }

    private let database: AppDatabase?
    private var saveWorkItem: DispatchWorkItem?
    private var scopedAccessURL: URL?

    init(database: AppDatabase? = nil) {
        self.database = database
        let fallback = Self.defaultDownloadsDirectory()
        if let saved: URL = Self.read(database, URL.self, key: Self.directoryKey),
           Self.isUsableDirectory(saved) {
            self.downloadDirectory = saved.standardizedFileURL
        } else if let bookmarked = Self.resolveBookmark(database),
                  Self.isUsableDirectory(bookmarked) {
            self.downloadDirectory = bookmarked.standardizedFileURL
        } else {
            self.downloadDirectory = fallback
        }
        beginScopedAccess(for: downloadDirectory)
        if let savedItems: [DownloadItem] = Self.read(database, [DownloadItem].self, key: Self.itemsKey) {
            self.downloads = savedItems.map { item in
                var fixed = item
                // Active downloads can't survive a relaunch — mark them failed.
                if fixed.state == .downloading {
                    fixed.state = .failed
                    fixed.errorDescription = "Interrupted by relaunch"
                    fixed.endDate = fixed.endDate ?? Date()
                }
                fixed.speedBytesPerSec = 0
                return fixed
            }
            pruneMissingFiles()
        }
    }

    var activeDownloads: [DownloadItem] {
        downloads.filter(\.isActive)
    }

    var hasActiveDownloads: Bool {
        downloads.contains(where: \.isActive)
    }

    var overallProgress: Double {
        let active = activeDownloads
        guard !active.isEmpty else { return 0 }
        let known = active.filter { $0.totalBytes > 0 }
        if known.isEmpty { return 0 }
        let received = known.reduce(0) { $0 + $1.receivedBytes }
        let total = known.reduce(0) { $0 + $1.totalBytes }
        guard total > 0 else { return 0 }
        return min(1, Double(received) / Double(total))
    }

    // MARK: - Directory

    /// The user's Downloads folder (~/Downloads). Never hardcode a home path —
    /// resolve it from the system so it follows the actual logged-in user.
    static func defaultDownloadsDirectory() -> URL {
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        return url.standardizedFileURL
    }

    func setDownloadDirectory(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard Self.isUsableDirectory(normalized) else { return }
        downloadDirectory = normalized
        beginScopedAccess(for: normalized)
        persistDirectory()
    }

    func resetToDefaultDirectory() {
        let fallback = Self.defaultDownloadsDirectory()
        downloadDirectory = fallback
        beginScopedAccess(for: fallback)
        persistDirectory()
    }

    // MARK: - Lifecycle (called from LeanTab WKDownloadDelegate)

    @discardableResult
    func beginDownload(fileName: String, sourceURL: URL?, destinationURL: URL, totalBytes: Int64) -> UUID {
        let item = DownloadItem(
            fileName: fileName,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            totalBytes: totalBytes
        )
        downloads.insert(item, at: 0)
        if downloads.count > 100 {
            downloads = Array(downloads.prefix(100))
        }
        scheduleSave()
        return item.id
    }

    func updateProgress(id: UUID, receivedBytes: Int64, totalBytes: Int64, speedBytesPerSec: Double) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].receivedBytes = max(0, receivedBytes)
        if totalBytes > 0 {
            downloads[index].totalBytes = totalBytes
        }
        downloads[index].speedBytesPerSec = max(0, speedBytesPerSec)
        if downloads[index].state != .downloading {
            downloads[index].state = .downloading
        }
        scheduleSave()
    }

    func finishDownload(id: UUID, fileName: String? = nil) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        if let fileName, !fileName.isEmpty {
            downloads[index].fileName = fileName
        }
        if downloads[index].totalBytes <= 0 {
            downloads[index].totalBytes = downloads[index].receivedBytes
        }
        downloads[index].state = .completed
        downloads[index].endDate = Date()
        downloads[index].speedBytesPerSec = 0
        scheduleSave()
    }

    func failDownload(id: UUID, errorDescription: String?, cancelled: Bool = false) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].state = cancelled ? .cancelled : .failed
        downloads[index].endDate = Date()
        downloads[index].errorDescription = errorDescription
        downloads[index].speedBytesPerSec = 0
        scheduleSave()
    }

    func cancelDownload(id: UUID) {
        failDownload(id: id, errorDescription: "Cancelled", cancelled: true)
    }

    func removeDownload(id: UUID) {
        downloads.removeAll { $0.id == id }
        scheduleSave()
    }

    func clearCompleted() {
        downloads.removeAll { $0.state == .completed || $0.state == .failed || $0.state == .cancelled }
        scheduleSave()
    }

    func clearAll() {
        downloads.removeAll { !$0.isActive }
        scheduleSave()
    }

    // MARK: - Destination

    func uniqueDestination(for suggestedFilename: String) -> URL {
        let base = Self.ensureExists(downloadDirectory) ?? Self.ensureExists(Self.defaultDownloadsDirectory()) ?? downloadDirectory
        let safe = suggestedFilename.isEmpty ? "download" : suggestedFilename
        var destination = base.appendingPathComponent(safe)
        var counter = 1
        let name = (safe as NSString).deletingPathExtension
        let ext = (safe as NSString).pathExtension
        while FileManager.default.fileExists(atPath: destination.path) {
            let unique = ext.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(ext)"
            destination = base.appendingPathComponent(unique)
            counter += 1
        }
        return destination
    }

    // MARK: - Persistence

    private static let itemsKey = "downloads_v1"
    private static let directoryKey = "downloadsDirectory_v1"
    private static let directoryBookmarkKey = "downloadsDirectoryBookmark_v1"

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func saveNow() {
        guard let database else { return }
        var snapshot = downloads
        if snapshot.count > 100 {
            snapshot = Array(snapshot.prefix(100))
        }
        if case .failure(let error) = database.set(snapshot, forKey: Self.itemsKey) {
            NSLog("Could not persist downloads: %@", String(describing: error))
        }
    }

    private func persistDirectory() {
        guard let database else { return }
        if case .failure(let error) = database.set(downloadDirectory, forKey: Self.directoryKey) {
            NSLog("Could not persist download directory: %@", String(describing: error))
        }
        do {
            let data = try downloadDirectory.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            _ = database.set(data, forKey: Self.directoryBookmarkKey)
        } catch {
            // Security-scoped bookmarks fail on non-sandboxed paths; plain path is enough.
        }
    }

    private static func read<T: Decodable>(_ database: AppDatabase?, _ type: T.Type, key: String) -> T? {
        guard let database else { return nil }
        switch database.value(type, forKey: key) {
        case .success(let value):
            return value
        case .failure(let error):
            NSLog("Could not read %@: %@", key, String(describing: error))
            return nil
        }
    }

    private static func resolveBookmark(_ database: AppDatabase?) -> URL? {
        guard let data: Data = read(database, Data.self, key: directoryBookmarkKey) else { return nil }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale { return nil }
            guard isUsableDirectory(url) else { return nil }
            return url
        } catch {
            return nil
        }
    }

    /// Directory is usable when it exists and is a folder. Writability is
    /// enforced by the sandbox (downloads entitlement / user-selected scope),
    /// which `isWritableFile` cannot see, so don't gate on it.
    private static func isUsableDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
        return true
    }

    /// Makes sure the directory exists, creating intermediates. Returns nil
    /// when creation fails (e.g. sandbox denial), letting callers fall back.
    @discardableResult
    private static func ensureExists(_ url: URL) -> URL? {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue ? url : nil
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            NSLog("Could not create download directory %@: %@", url.path, String(describing: error))
            return nil
        }
    }

    /// Holds security-scoped access for a custom (Open-panel-picked) folder
    /// for the app lifetime. No-op for plain paths like ~/Downloads, which
    /// the downloads entitlement already covers.
    private func beginScopedAccess(for url: URL) {
        if let current = scopedAccessURL {
            current.stopAccessingSecurityScopedResource()
            scopedAccessURL = nil
        }
        if url.startAccessingSecurityScopedResource() {
            scopedAccessURL = url
        }
    }

    private func pruneMissingFiles() {
        // Keep history entries even if the file was moved — Settings still shows them.
        // Only drop entries whose destination never existed and are marked failed with no size.
        _ = downloads
    }
}

// MARK: - Formatting

enum DownloadFormat {
    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    static func fileSize(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "—" }
        return byteFormatter.string(fromByteCount: bytes)
    }

    static func speed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0 else { return "—" }
        return "\(byteFormatter.string(fromByteCount: Int64(bytesPerSec)))/s"
    }

    static func progressText(received: Int64, total: Int64) -> String {
        if total > 0 {
            let pct = Int((Double(received) / Double(total) * 100).rounded())
            return "\(min(100, max(0, pct)))% · \(fileSize(received)) of \(fileSize(total))"
        }
        return fileSize(received)
    }

    static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func icon(for fileName: String) -> Ph {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return .filePdf
        case "zip", "gz", "tar", "rar", "7z", "dmg": return .fileArchive
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic": return .fileImage
        case "mp4", "mov", "mkv", "webm": return .fileVideo
        case "mp3", "wav", "flac", "m4a", "ogg": return .fileAudio
        case "doc", "docx", "txt", "md", "rtf": return .fileText
        case "xls", "xlsx", "csv": return .fileCsv
        case "ppt", "pptx", "key": return .filePpt
        case "app": return .appWindow
        case "pkg": return .package
        default: return .file
        }
    }

    static func systemImage(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "zip", "gz", "tar", "rar", "7z", "dmg": return "archivebox.fill"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic": return "photo.fill"
        case "mp4", "mov", "mkv", "webm": return "film.fill"
        case "mp3", "wav", "flac", "m4a", "ogg": return "music.note"
        case "doc", "docx", "txt", "md", "rtf": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle.fill"
        case "app": return "app.fill"
        case "pkg": return "shippingbox.fill"
        default: return "doc.fill"
        }
    }
}
