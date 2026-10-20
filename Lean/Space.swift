import SwiftUI
import WebKit

/// A separate browsing context: its own tabs, cookies, logins, storage and
/// cache, history, bookmarks, recently closed tabs and download list.
/// Settings, extensions and the download folder are shared.
struct Space: Identifiable, Codable, Equatable {
    /// Where a space's website data lives.
    enum WebsiteData: Codable, Equatable {
        /// WebKit's default store: the data Lean had before spaces existed.
        case shared
        /// A store of its own, named by this identifier.
        case separate(UUID)
    }

    let id: UUID
    var name: String
    let websiteData: WebsiteData
    var theme: SpaceTheme

    /// The first space. It keeps the data and session Lean already had.
    static func personal() -> Space {
        Space(id: UUID(), name: "Personal", websiteData: .shared, theme: .none)
    }

    static func new(named name: String, theme: SpaceTheme) -> Space {
        let id = UUID()
        return Space(id: id, name: name, websiteData: .separate(id), theme: theme)
    }
}

/// The tint a space wears on the window frame: up to three colours picked
/// on a pad, how strongly they show, and how much grain sits over them.
struct SpaceTheme: Codable, Equatable {
    /// A spot on the colour pad, both axes 0…1: x is the hue, y runs from
    /// vivid at the top to soft at the bottom.
    struct PadPoint: Codable, Equatable {
        var x: Double
        var y: Double

        var color: Color {
            Color(hue: x, saturation: 0.85 - 0.55 * y, brightness: 0.95 - 0.25 * y)
        }
    }

    static let maxColors = 3

    var points: [PadPoint]
    /// How strongly the tint shows, 0…1.
    var intensity: Double
    /// Film grain over the tint, 0…1.
    var grain: Double

    static let none = SpaceTheme(points: [], intensity: 0.6, grain: 0)

    /// A theme with one colour, as a swatch sets it.
    static func swatch(_ point: PadPoint) -> SpaceTheme {
        SpaceTheme(points: [point], intensity: 0.6, grain: 0)
    }

    var isTinted: Bool { !points.isEmpty && intensity > 0 }

    var colors: [Color] { points.map(\.color) }

    /// The swatch row under the pad.
    static let swatches: [PadPoint] = [
        PadPoint(x: 0.92, y: 0.45), PadPoint(x: 0.58, y: 0.25), PadPoint(x: 0.72, y: 0.35),
        PadPoint(x: 0.97, y: 0.55), PadPoint(x: 0.0, y: 0.4), PadPoint(x: 0.07, y: 0.2),
        PadPoint(x: 0.13, y: 0.15), PadPoint(x: 0.42, y: 0.35), PadPoint(x: 0.5, y: 0.6),
        PadPoint(x: 0.8, y: 0.1), PadPoint(x: 0.33, y: 0.7), PadPoint(x: 0.0, y: 0.85),
    ]
}

extension Space {
    /// The store a space's tabs load into. A store injected for tests or a
    /// private window stands in for the shared one, and keeps every separate
    /// space in memory too, so neither ever writes to disk.
    @MainActor
    func makeDataStore(injected: WKWebsiteDataStore?) -> WKWebsiteDataStore {
        switch websiteData {
        case .shared:
            return injected ?? .default()
        case .separate(let identifier):
            return injected == nil ? WKWebsiteDataStore(forIdentifier: identifier) : .nonPersistent()
        }
    }
}
