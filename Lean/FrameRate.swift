// Adapted from Search by Office Commun, licensed under the MIT License.
// Copyright (c) 2026 Office Commun. See the Search repository LICENSE.
import WebKit

// Pages at 120 Hz, on a screen that can go that fast, like a MacBook Pro's.
//
// WebKit holds a page's animations, and the scrolling it draws itself, to
// about 60 frames a second even on a 120 Hz screen. That's Safari's default
// too, and it is the cheaper one: a page that animates at 120 draws twice as
// often, and in a short test on a 120 Hz MacBook Pro, a page with one CSS
// animation took about half again as much energy (Activity Monitor's 10 → 15).
// A page that is standing still costs nothing either way. So 60 unless
// asked for, in Settings › General › Pages at 120 Hz.
//
// Off, WebKit's flag is not touched at all: a page gets whatever this Mac's
// WebKit does on its own, the same as Safari.

enum FrameRate {
    /// Settings › General › Pages at 120 Hz. Read when a page's
    /// configuration is made; open pages are re-applied by the store.
    @MainActor static var fast = false

    /// The preferences this has taken past 60, so switching off can undo
    /// exactly those and nothing else.
    @MainActor private static let changed = NSHashTable<WKPreferences>.weakObjects()

    /// Before a page's view is made, which is when WebKit reads the flag:
    /// a new tab, one opened by a site, and one woken from sleep.
    @MainActor static func apply(to preferences: WKPreferences) {
        if fast {
            guard near60 != nil else { return }
            set(false, in: preferences)
            changed.add(preferences)
        }
    }

    /// Give open pages WebKit's own rate back — only those this changed.
    @MainActor static func restoreChanged() {
        for preferences in changed.allObjects { set(true, in: preferences) }
        changed.removeAllObjects()
    }

    /// Whether the page holds itself near 60, as its WebKit has it — nil
    /// where this WebKit has no such flag.
    static func prefersNear60(_ preferences: WKPreferences) -> Bool? {
        let get = NSSelectorFromString("_isEnabledForFeature:")
        guard let flag = near60, preferences.responds(to: get) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        return unsafeBitCast(preferences.method(for: get), to: Getter.self)(preferences, get, flag)
    }

    // MARK: - WebKit's switch

    /// The switch is one of WebKit's feature flags, the list Safari shows
    /// under Develop › Feature Flags. It isn't in the public framework, so
    /// each step is asked first, and a WebKit without it is left alone.
    /// Looked up once: the list has a few hundred entries, and walking it
    /// for every tab would be for nothing.
    private static let near60: NSObject? = {
        let list = NSSelectorFromString("_features")
        let type: AnyObject = WKPreferences.self
        guard type.responds(to: list),
              let all = type.perform(list)?.takeUnretainedValue() as? [NSObject]
        else { return nil }
        return all.first { $0.value(forKey: "key") as? String == "PreferPageRenderingUpdatesNear60FPSEnabled" }
    }()

    private static func set(_ on: Bool, in preferences: WKPreferences) {
        let set = NSSelectorFromString("_setEnabled:forFeature:")
        guard let flag = near60, preferences.responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        unsafeBitCast(preferences.method(for: set), to: Setter.self)(preferences, set, on, flag)
    }
}
