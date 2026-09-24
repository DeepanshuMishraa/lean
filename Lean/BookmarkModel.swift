import Foundation

public struct BookmarkItem: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var url: URL
    public var folder: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        folder: String = BookmarkFolder.defaultFolder,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.folder = folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BookmarkFolder.defaultFolder : folder
        self.createdAt = createdAt
    }

    public var host: String {
        guard let host = url.host?.lowercased() else { return url.absoluteString }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

public struct BookmarkFolder: Codable, Identifiable, Hashable, Sendable {
    public static let defaultFolder = "Favorites"
    public static let allFolder = "All"

    public var id: String { name }
    public let name: String

    public init(name: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultFolder : name
    }
}
