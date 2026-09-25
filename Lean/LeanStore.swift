import AppKit
import Combine
import Foundation
import SwiftUI
import WebKit

private struct BrowserUIScaleEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var browserUIScale: CGFloat {
        get { self[BrowserUIScaleEnvironmentKey.self] }
        set { self[BrowserUIScaleEnvironmentKey.self] = newValue }
    }
}

enum FloatingOmnibarMode {
    case newTab
    case navigate
}

enum TabDisplayMode: String, CaseIterable, Identifiable {
    case textOnly = "textOnly"
    case iconOnly = "iconOnly"
    case hybrid = "hybrid"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .textOnly: return "Text Only"
        case .iconOnly: return "Icon Only"
        case .hybrid: return "Hybrid"
        }
    }

    var subtitle: String {
        switch self {
        case .textOnly: return "Titles only"
        case .iconOnly: return "Icons only"
        case .hybrid: return "Icons & titles"
        }
    }
}

enum TabLayout: String, CaseIterable, Identifiable, Codable {
    case top = "top"
    case sidebar = "sidebar"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "Top of Window"
        case .sidebar: return "Sidebar"
        }
    }

    var subtitle: String {
        switch self {
        case .top: return "Horizontal tabs above web content"
        case .sidebar: return "Vertical tabs in collapsible left sidebar"
        }
    }
}

enum ToolbarItemType: String, CaseIterable, Identifiable, Codable, Equatable, Hashable {
    case back = "back"
    case forward = "forward"
    case reload = "reload"
    case newTab = "newTab"
    case extensions = "extensions"
    case downloads = "downloads"
    case bookmarks = "bookmarks"
    case themeToggle = "themeToggle"
    case settings = "settings"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .back: return "Back"
        case .forward: return "Forward"
        case .reload: return "Reload"
        case .newTab: return "New Tab"
        case .extensions: return "Extensions"
        case .downloads: return "Downloads"
        case .bookmarks: return "Bookmarks"
        case .themeToggle: return "Theme"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .reload: return "arrow.clockwise"
        case .newTab: return "plus"
        case .extensions: return "puzzlepiece.extension"
        case .downloads: return "arrow.down.circle"
        case .bookmarks: return "bookmark"
        case .themeToggle: return "sun.max.fill"
        case .settings: return "gearshape"
        }
    }

    var icon: LeanIcon {
        switch self {
        case .back: return .caretLeft
        case .forward: return .caretRight
        case .reload: return .arrowClockwise
        case .newTab: return .plus
        case .extensions: return .extension
        case .downloads: return .arrowCircleDown
        case .bookmarks: return .bookmark
        case .themeToggle: return .sun
        case .settings: return .gear
        }
    }

    var isNavigationItem: Bool {
        switch self {
        case .back, .forward, .reload:
            return true
        case .newTab, .extensions, .downloads, .bookmarks, .themeToggle, .settings:
            return false
        }
    }
}

private struct BrowserSession: Codable {
    var urls: [String]
    var selectedIndex: Int
    var pinnedIndices: [Int]?
}

struct HistoryItem: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let timestamp: Date

    init(id: UUID = UUID(), url: URL, title: String, timestamp: Date = Date()) {
        self.id = id
        self.url = url
        self.title = title
        self.timestamp = timestamp
    }
}

@MainActor
final class LeanStore: ObservableObject {
    @Published private(set) var tabs: [LeanTab] = []
    var pinnedTabs: [LeanTab] {
        tabs.filter(\.isPinned)
    }
    var unpinnedTabs: [LeanTab] {
        tabs.filter { !$0.isPinned }
    }
    @Published var selectedID: LeanTab.ID? {
        didSet { handleTabSelectionChange(from: oldValue, to: selectedID) }
    }
    @Published var showsFindBar = false
    @Published var isFloatingOmnibarVisible = false
    @Published var floatingOmnibarMode: FloatingOmnibarMode = .newTab
    @Published var isInlineURLEditing = false
    @Published var isNewTabOmnibarFloating = false
    @Published var showsSettings = false
    @Published var floatingPaletteFrame: CGRect = .zero
    @Published var inlineURLBarFrame: CGRect = .zero
    @Published var inlineSuggestionsFrame: CGRect = .zero
    @Published var isTabSwitcherVisible = false
    @Published var switcherSelectedIndex = 0
    @Published var historyItems: [HistoryItem] = []
    @Published private(set) var importedBookmarks: [ImportedBookmark] = []
    @Published var bookmarks: [BookmarkItem] = []
    @Published var bookmarkFolders: [String] = [BookmarkFolder.defaultFolder]
    @Published var selectedBookmarkFolder: String = BookmarkFolder.allFolder
    @Published var isBookmarksPresented = false
    @Published var bookmarksButtonFrame: CGRect = .zero
    @Published var bookmarksPaletteFrame: CGRect = .zero
    @Published var isBookmarkDialogPresented = false
    @Published var dialogBookmarkTitle = ""
    @Published var dialogBookmarkFolder = BookmarkFolder.defaultFolder
    @Published var dialogBookmarkURL: URL? = nil
    @Published var dialogBookmarkFrame: CGRect = .zero
    @Published var selectedSettingsCategory: SettingsCategory = .general
    @Published var isQuickSettingsPresented = false
    @Published var quickSettingsPopoverFrame: CGRect = .zero
    @Published var quickSettingsSubmenuFrame: CGRect = .zero
    @Published var settingsButtonFrame: CGRect = .zero
    @Published var isDownloadsPresented = false
    @Published var downloadsButtonFrame: CGRect = .zero
    @Published var downloadsPopoverFrame: CGRect = .zero
    @Published var isExtensionsPresented = false
    @Published var extensionsButtonFrame: CGRect = .zero
    @Published var extensionsPopoverFrame: CGRect = .zero
    @Published var downloadManager: DownloadManager
    @Published var customShortcuts: [String: CustomKeyCombo] = [:] {
        didSet {
            saveCustomShortcuts()
        }
    }
    var visitedHistory: [(url: URL, title: String)] {
        historyItems.map { ($0.url, $0.title) }
    }

    @Published var searchEngine: SearchEngine {
        didSet {
            persist(searchEngine.rawValue, forKey: Self.searchEngineKey)
        }
    }

    @Published var adBlockingEnabled: Bool {
        didSet {
            persist(adBlockingEnabled, forKey: Self.adBlockingKey)
            updateAllTabsAdBlocking()
        }
    }
    @Published private(set) var adBlockingExcludedHosts: Set<String> = []

    @Published var passwordSavePromptsEnabled = true {
        didSet {
            persist(passwordSavePromptsEnabled, forKey: Self.passwordSavePromptsKey)
            updateAllTabsPasswordPreferences()
        }
    }

    @Published var passwordSuggestionsEnabled = true {
        didSet {
            persist(passwordSuggestionsEnabled, forKey: Self.passwordSuggestionsKey)
            updateAllTabsPasswordPreferences()
        }
    }

    /// Whether sites may use passkeys (Touch ID / iCloud / security key).
    /// Defaults to whether this build carries Apple's browser entitlement;
    /// without it the switch stays off and sites fall back to passwords.
    @Published var passkeysEnabled = Passkeys.isEntitled {
        didSet {
            persist(passkeysEnabled, forKey: Self.passkeysEnabledKey)
            Passkeys.isEnabled = passkeysEnabled
            updateAllTabsPasskeys()
        }
    }

    /// Whether this build can actually do passkeys: signed with Apple's
    /// browser entitlement. Fixed for the life of the process.
    let passkeysPossible = Passkeys.isEntitled

    @Published var autoSleepTabsEnabled = false {
        didSet {
            persist(autoSleepTabsEnabled, forKey: Self.autoSleepTabsEnabledKey)
            scheduleAutoSleep()
        }
    }

    @Published var autoSleepAfterMinutes = 30 {
        didSet {
            persist(autoSleepAfterMinutes, forKey: Self.autoSleepAfterMinutesKey)
            scheduleAutoSleep()
        }
    }

    @Published var theme: AppTheme {
        didSet {
            persist(theme.rawValue, forKey: Self.themeKey)
            updateAllTabsTheme()
        }
    }

    @Published var scrollbarStyle: ScrollbarStyle {
        didSet {
            persist(scrollbarStyle.rawValue, forKey: Self.scrollbarKey)
            updateAllTabsScrollbarStyle()
        }
    }

    @Published var tabDisplayMode: TabDisplayMode {
        didSet {
            persist(tabDisplayMode.rawValue, forKey: Self.tabDisplayModeKey)
        }
    }

    @Published var enableThumbnailsInTabSwitcher: Bool {
        didSet {
            persist(enableThumbnailsInTabSwitcher, forKey: Self.thumbnailsSwitcherKey)
        }
    }

    @Published var smoothScrollingEnabled: Bool {
        didSet {
            persist(smoothScrollingEnabled, forKey: Self.smoothScrollingKey)
            updateAllTabsSmoothScrolling()
        }
    }

    /// The top strip takes the colour the active page declares for itself
    /// with `theme-color`, and follows it from tab to tab. Only the strip
    /// across the top — the sidebar layout is unaffected, and a page that
    /// hasn't declared a colour leaves the strip as it always looked. Off
    /// unless asked for.
    @Published var themedTabBar: Bool {
        didSet {
            persist(themedTabBar, forKey: Self.themedTabBarKey)
        }
    }

    @Published var highFrameRatePages: Bool {
        didSet {
            persist(highFrameRatePages, forKey: Self.highFrameRatePagesKey)
            updateAllTabsHighFrameRate()
        }
    }

    /// A link's page, peeked at over this one (see PeekPanel). Off unless
    /// asked for, in Settings › General.
    @Published var peekTab: LeanTab?

    /// Shift-click on a link opens it in a panel over the page. Off unless
    /// asked for.
    @Published var peeksLinks: Bool {
        didSet {
            persist(peeksLinks, forKey: Self.peeksLinksKey)
            updateAllTabsPeekPreferences()
        }
    }

    @Published var showFullTitleOnActiveTab: Bool {
        didSet {
            persist(showFullTitleOnActiveTab, forKey: Self.showFullTitleKey)
        }
    }

    @Published var leanUIFont: LeanFont {
        didSet {
            persist(leanUIFont.rawValue, forKey: Self.leanUIFontKey)
        }
    }

    @Published var uiHeadingWeight: LeanFontWeight {
        didSet {
            persist(uiHeadingWeight.rawValue, forKey: Self.uiHeadingWeightKey)
        }
    }

    @Published var uiBodyWeight: LeanFontWeight {
        didSet {
            persist(uiBodyWeight.rawValue, forKey: Self.uiBodyWeightKey)
        }
    }

    @Published var browserUIScalePercent: Int {
        didSet {
            let clamped = min(120, max(80, browserUIScalePercent))
            if browserUIScalePercent != clamped {
                browserUIScalePercent = clamped
                return
            }
            persist(browserUIScalePercent, forKey: Self.browserUIScaleKey)
        }
    }

    var browserUIScale: CGFloat { CGFloat(browserUIScalePercent) / 100 }

    func scaled(_ value: CGFloat) -> CGFloat { value * browserUIScale }

    func headingFont(size: CGFloat) -> Font {
        leanUIFont.font(size: scaled(size), fontWeight: uiHeadingWeight)
    }

    func headingFont(size: CGFloat, weight: LeanFontWeight) -> Font {
        leanUIFont.font(size: scaled(size), fontWeight: weight)
    }

    var tabTitleTypeface: LeanFont {
        leanUIFont
    }

    func tabTitleFont(size: CGFloat) -> Font {
        leanUIFont.font(size: scaled(size), fontWeight: uiHeadingWeight)
    }

    func bodyFont(size: CGFloat) -> Font {
        leanUIFont.font(size: scaled(size), fontWeight: uiBodyWeight)
    }

    func bodyFont(size: CGFloat, weight: LeanFontWeight) -> Font {
        leanUIFont.font(size: scaled(size), fontWeight: weight)
    }

    @Published var webPageFont: LeanFont {
        didSet {
            persist(webPageFont.rawValue, forKey: Self.webPageFontKey)
            updateAllTabsFonts()
        }
    }

    @Published var enableZenMode: Bool {
        didSet {
            persist(enableZenMode, forKey: Self.zenModeKey)
        }
    }

    @Published var tabLayout: TabLayout {
        didSet {
            persist(tabLayout.rawValue, forKey: Self.tabLayoutKey)
            if tabLayout == .sidebar {
                enableWindowBorder = true
            }
        }
    }

    @Published var isSidebarCollapsed: Bool {
        didSet {
            persist(isSidebarCollapsed, forKey: Self.isSidebarCollapsedKey)
        }
    }

    func toggleSidebar() {
        isSidebarCollapsed.toggle()
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
    }

    @Published var enableWindowBorder: Bool {
        didSet {
            if tabLayout == .sidebar && !enableWindowBorder {
                enableWindowBorder = true
                return
            }
            persist(enableWindowBorder, forKey: Self.windowBorderKey)
        }
    }

    @Published var windowBorderColor: Color {
        didSet {
            persist(windowBorderColor.toHex(), forKey: Self.windowBorderColorKey)
        }
    }

    @Published var windowBorderWidth: CGFloat {
        didSet {
            persist(Double(windowBorderWidth), forKey: Self.windowBorderWidthKey)
        }
    }

    @Published var shownToolbarItems: [ToolbarItemType] {
        didSet {
            persist(shownToolbarItems.map(\.rawValue), forKey: Self.shownToolbarItemsKey)
        }
    }

    @Published var hiddenToolbarItems: [ToolbarItemType] {
        didSet {
            persist(hiddenToolbarItems.map(\.rawValue), forKey: Self.hiddenToolbarItemsKey)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            persist(hasCompletedOnboarding, forKey: Self.hasCompletedOnboardingKey)
        }
    }
    @Published var isOnboardingPresented: Bool = false

    func startOnboarding() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            isOnboardingPresented = true
        }
    }

    func completeOnboarding() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            hasCompletedOnboarding = true
            isOnboardingPresented = false
        }
    }

    private let dataStore: WKWebsiteDataStore
    private let database: AppDatabase?
    let mediaPermissionStore: MediaPermissionStore
    private var recentlyClosed: [URL] = []
    private var adBlockUpdateObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var inactiveSince: [LeanTab.ID: Date] = [:]
    private var sleepWorkItems: [LeanTab.ID: DispatchWorkItem] = [:]
    private var sleepWorkTokens: [LeanTab.ID: UUID] = [:]
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private let pictureInPicture = PictureInPicture()
    private var pictureInPictureTabID: LeanTab.ID?
    /// Tab currently being reordered via native drag & drop. Plain (not
    /// @Published) on purpose: it is only read by drop delegates mid-drag.
    var draggingTabID: LeanTab.ID?

    init(dataStore: WKWebsiteDataStore? = nil, database: AppDatabase? = nil) {
        self.dataStore = dataStore ?? WKWebsiteDataStore.default()
        self.database = database ?? AppDatabase.openDefault()
        self.downloadManager = DownloadManager(database: self.database)
        self.mediaPermissionStore = MediaPermissionStore(database: self.database)

        let savedSearchEngine = databaseValue(self.database, String.self, forKey: Self.searchEngineKey)
            ?? UserDefaults.standard.string(forKey: Self.searchEngineKey)
            ?? SearchEngine.google.rawValue
        self.searchEngine = SearchEngine(rawValue: savedSearchEngine) ?? .google

        let savedAdBlocking = databaseValue(self.database, Bool.self, forKey: Self.adBlockingKey)
            ?? UserDefaults.standard.object(forKey: Self.adBlockingKey) as? Bool
            ?? true
        self.adBlockingEnabled = savedAdBlocking
        self.adBlockingExcludedHosts = databaseValue(self.database, Set<String>.self, forKey: Self.adBlockingExcludedHostsKey) ?? []
        self.passwordSavePromptsEnabled = databaseValue(self.database, Bool.self, forKey: Self.passwordSavePromptsKey) ?? true
        self.passwordSuggestionsEnabled = databaseValue(self.database, Bool.self, forKey: Self.passwordSuggestionsKey) ?? true
        let savedPasskeys = databaseValue(self.database, Bool.self, forKey: Self.passkeysEnabledKey)
        // A choice made while passkeys couldn't work is not a choice about
        // them: default to what this build can do.
        let initialPasskeys = savedPasskeys ?? Passkeys.isEntitled
        self.passkeysEnabled = initialPasskeys
        Passkeys.isEnabled = initialPasskeys
        self.autoSleepTabsEnabled = databaseValue(self.database, Bool.self, forKey: Self.autoSleepTabsEnabledKey) ?? false
        let savedSleepMinutes = databaseValue(self.database, Int.self, forKey: Self.autoSleepAfterMinutesKey) ?? 30
        self.autoSleepAfterMinutes = [5, 15, 30, 60].contains(savedSleepMinutes) ? savedSleepMinutes : 30

        if let savedHistory = databaseValue(self.database, [HistoryItem].self, forKey: Self.historyKey) {
            self.historyItems = savedHistory
        } else if let savedHistory = UserDefaults.standard.array(forKey: Self.historyKey) as? [[String: Any]] {
            self.historyItems = savedHistory.compactMap { item in
                guard let rawURL = item["url"] as? String,
                      let url = URL(string: rawURL),
                      let title = item["title"] as? String else { return nil }
                let timestamp: Date
                if let timeVal = item["timestamp"] as? Double {
                    timestamp = Date(timeIntervalSince1970: timeVal)
                } else {
                    timestamp = Date()
                }
                return HistoryItem(url: url, title: title, timestamp: timestamp)
            }
        } else if let savedHistoryLegacy = UserDefaults.standard.array(forKey: Self.historyKey) as? [[String: String]] {
            self.historyItems = savedHistoryLegacy.compactMap { item in
                guard let rawURL = item["url"], let url = URL(string: rawURL), let title = item["title"] else { return nil }
                return HistoryItem(url: url, title: title, timestamp: Date())
            }
        }

        let loadedImportedBookmarks = databaseValue(self.database, [ImportedBookmark].self, forKey: Self.importedBookmarksKey) ?? []
        self.importedBookmarks = loadedImportedBookmarks

        // Load bookmark folders
        let savedFolders = databaseValue(self.database, [String].self, forKey: Self.bookmarkFoldersKey)
            ?? UserDefaults.standard.stringArray(forKey: Self.bookmarkFoldersKey)
        var folders = savedFolders ?? [BookmarkFolder.defaultFolder]
        if !folders.contains(BookmarkFolder.defaultFolder) {
            folders.insert(BookmarkFolder.defaultFolder, at: 0)
        }
        self.bookmarkFolders = folders

        // Load bookmarks (with migration from importedBookmarks on first run)
        let savedBookmarks = databaseValue(self.database, [BookmarkItem].self, forKey: Self.bookmarksKey)
        if let savedBookmarks = savedBookmarks {
            self.bookmarks = savedBookmarks
        } else {
            let migrated: [BookmarkItem] = loadedImportedBookmarks.map {
                BookmarkItem(id: $0.id, title: $0.title, url: $0.url, folder: BookmarkFolder.defaultFolder)
            }
            self.bookmarks = migrated
        }

        // Load saved theme (default to light or saved preference)
        let savedTheme = databaseValue(self.database, String.self, forKey: Self.themeKey)
            ?? UserDefaults.standard.string(forKey: Self.themeKey)
            ?? AppTheme.light.rawValue
        self.theme = AppTheme(rawValue: savedTheme) ?? .light

        // Load saved scrollbar style (default to normal)
        let savedScrollbar = databaseValue(self.database, String.self, forKey: Self.scrollbarKey)
            ?? UserDefaults.standard.string(forKey: Self.scrollbarKey)
            ?? ScrollbarStyle.normal.rawValue
        self.scrollbarStyle = ScrollbarStyle(rawValue: savedScrollbar) ?? .normal

        // Load saved tab display mode (default to textOnly)
        let savedTabDisplay = databaseValue(self.database, String.self, forKey: Self.tabDisplayModeKey)
            ?? UserDefaults.standard.string(forKey: Self.tabDisplayModeKey)
            ?? TabDisplayMode.textOnly.rawValue
        self.tabDisplayMode = TabDisplayMode(rawValue: savedTabDisplay) ?? .textOnly

        // Load saved tab switcher thumbnail preference (default to true)
        let savedThumbnails = databaseValue(self.database, Bool.self, forKey: Self.thumbnailsSwitcherKey)
            ?? UserDefaults.standard.object(forKey: Self.thumbnailsSwitcherKey) as? Bool
            ?? true
        self.enableThumbnailsInTabSwitcher = savedThumbnails

        // Load saved smooth scrolling preference (default to true)
        let savedSmoothScrolling = databaseValue(self.database, Bool.self, forKey: Self.smoothScrollingKey)
            ?? UserDefaults.standard.object(forKey: Self.smoothScrollingKey) as? Bool
            ?? true
        self.smoothScrollingEnabled = savedSmoothScrolling

        // Colour the tab bar from the page (default off).
        let savedThemedTabBar = databaseValue(self.database, Bool.self, forKey: Self.themedTabBarKey)
            ?? UserDefaults.standard.object(forKey: Self.themedTabBarKey) as? Bool
            ?? false
        self.themedTabBar = savedThemedTabBar

        // Pages at 120 Hz (default off: it costs energy, and a still page
        // costs nothing either way). Takes effect for new pages at once.
        let savedHighFrameRate = databaseValue(self.database, Bool.self, forKey: Self.highFrameRatePagesKey)
            ?? UserDefaults.standard.object(forKey: Self.highFrameRatePagesKey) as? Bool
            ?? false
        self.highFrameRatePages = savedHighFrameRate
        FrameRate.fast = savedHighFrameRate

        // Peek at a link with a shift-click (default off).
        let savedPeeksLinks = databaseValue(self.database, Bool.self, forKey: Self.peeksLinksKey)
            ?? UserDefaults.standard.object(forKey: Self.peeksLinksKey) as? Bool
            ?? false
        self.peeksLinks = savedPeeksLinks

        // Load saved show full title preference (default to true)
        let savedShowFullTitle = databaseValue(self.database, Bool.self, forKey: Self.showFullTitleKey)
            ?? UserDefaults.standard.object(forKey: Self.showFullTitleKey) as? Bool
            ?? true
        self.showFullTitleOnActiveTab = savedShowFullTitle

        let defaultFont = LeanFont.geistSans.rawValue
        let hasMigratedFontToGeist = databaseValue(self.database, Bool.self, forKey: "hasMigratedFontToGeistV2")
            ?? UserDefaults.standard.bool(forKey: "hasMigratedFontToGeistV2")

        let savedLeanUIFont: String
        let savedWebPageFont: String
        if !hasMigratedFontToGeist {
            savedLeanUIFont = defaultFont
            savedWebPageFont = defaultFont
            UserDefaults.standard.set(defaultFont, forKey: Self.leanUIFontKey)
            UserDefaults.standard.set(defaultFont, forKey: Self.webPageFontKey)
            UserDefaults.standard.set(true, forKey: "hasMigratedFontToGeistV2")
        } else {
            savedLeanUIFont = databaseValue(self.database, String.self, forKey: Self.leanUIFontKey)
                ?? UserDefaults.standard.string(forKey: Self.leanUIFontKey)
                ?? defaultFont
            savedWebPageFont = databaseValue(self.database, String.self, forKey: Self.webPageFontKey)
                ?? UserDefaults.standard.string(forKey: Self.webPageFontKey)
                ?? defaultFont
        }
        self.leanUIFont = LeanFont(rawValue: savedLeanUIFont)

        let savedHeadingWeight = databaseValue(self.database, Int.self, forKey: Self.uiHeadingWeightKey)
            ?? UserDefaults.standard.object(forKey: Self.uiHeadingWeightKey) as? Int
            ?? LeanFontWeight.semibold.rawValue
        self.uiHeadingWeight = LeanFontWeight(rawValue: savedHeadingWeight) ?? .semibold

        let savedBodyWeight = databaseValue(self.database, Int.self, forKey: Self.uiBodyWeightKey)
            ?? UserDefaults.standard.object(forKey: Self.uiBodyWeightKey) as? Int
            ?? LeanFontWeight.regular.rawValue
        self.uiBodyWeight = LeanFontWeight(rawValue: savedBodyWeight) ?? .regular

        let savedBrowserUIScale = databaseValue(self.database, Int.self, forKey: Self.browserUIScaleKey)
            ?? UserDefaults.standard.object(forKey: Self.browserUIScaleKey) as? Int
            ?? 100
        self.browserUIScalePercent = min(120, max(80, savedBrowserUIScale))

        self.webPageFont = LeanFont(rawValue: savedWebPageFont)

        let savedZen = databaseValue(self.database, Bool.self, forKey: Self.zenModeKey)
            ?? UserDefaults.standard.object(forKey: Self.zenModeKey) as? Bool
            ?? false
        self.enableZenMode = savedZen

        let savedTabLayout = databaseValue(self.database, String.self, forKey: Self.tabLayoutKey)
            ?? UserDefaults.standard.string(forKey: Self.tabLayoutKey)
            ?? TabLayout.top.rawValue
        let resolvedTabLayout = TabLayout(rawValue: savedTabLayout) ?? .top
        self.tabLayout = resolvedTabLayout

        let savedSidebarCollapsed = databaseValue(self.database, Bool.self, forKey: Self.isSidebarCollapsedKey)
            ?? UserDefaults.standard.object(forKey: Self.isSidebarCollapsedKey) as? Bool
            ?? false
        self.isSidebarCollapsed = savedSidebarCollapsed

        let savedBorder = databaseValue(self.database, Bool.self, forKey: Self.windowBorderKey)
            ?? UserDefaults.standard.object(forKey: Self.windowBorderKey) as? Bool
            ?? false
        self.enableWindowBorder = resolvedTabLayout == .sidebar ? true : savedBorder

        let savedBorderHex = databaseValue(self.database, String.self, forKey: Self.windowBorderColorKey)
            ?? UserDefaults.standard.string(forKey: Self.windowBorderColorKey)
            ?? "#2C2D32"
        self.windowBorderColor = Color(hex: savedBorderHex)

        let savedBorderWidth = databaseValue(self.database, Double.self, forKey: Self.windowBorderWidthKey)
            ?? UserDefaults.standard.object(forKey: Self.windowBorderWidthKey) as? Double
            ?? 8.0
        self.windowBorderWidth = CGFloat(savedBorderWidth)

        // Load saved toolbar items (default to all shown, none hidden)
        let savedShown = databaseValue(self.database, [String].self, forKey: Self.shownToolbarItemsKey)
            ?? UserDefaults.standard.stringArray(forKey: Self.shownToolbarItemsKey)
        let savedHidden = databaseValue(self.database, [String].self, forKey: Self.hiddenToolbarItemsKey)
            ?? UserDefaults.standard.stringArray(forKey: Self.hiddenToolbarItemsKey)
        if let savedShown = savedShown {
            var shown = savedShown.compactMap { ToolbarItemType(rawValue: $0) }
            let hidden = (savedHidden ?? []).compactMap { ToolbarItemType(rawValue: $0) }
            // Ensure any newly added ToolbarItemType cases are present
            for item in ToolbarItemType.allCases {
                if !shown.contains(item) && !hidden.contains(item) {
                    shown.append(item)
                }
            }
            self.shownToolbarItems = shown
            self.hiddenToolbarItems = hidden
        } else {
            self.shownToolbarItems = ToolbarItemType.allCases
            self.hiddenToolbarItems = []
        }

        // Onboarding shows exactly once: only when it was never completed.
        // (During testing this was forced on every launch; that override
        // is gone — a completed onboarding stays completed.)
        let completedOnboarding = databaseValue(self.database, Bool.self, forKey: Self.hasCompletedOnboardingKey)
            ?? UserDefaults.standard.object(forKey: Self.hasCompletedOnboardingKey) as? Bool
            ?? false
        self.hasCompletedOnboarding = completedOnboarding
        self.isOnboardingPresented = !completedOnboarding

        deduplicateHistory()
        saveHistory()
        if savedBookmarks == nil && !self.bookmarks.isEmpty {
            persist(self.bookmarks, forKey: Self.bookmarksKey)
        }

        adBlockUpdateObserver = NotificationCenter.default.addObserver(
            forName: ContentBlocker.didUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateAllTabsAdBlocking()
            }
        }
        ContentBlocker.refreshIfNeeded()
        configureMemoryPressureHandling()
        loadCustomShortcuts()
        downloadManager.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        let savedSession = databaseValue(self.database, BrowserSession.self, forKey: Self.sessionStateKey)
        let legacySessionURLs = databaseValue(self.database, [String].self, forKey: Self.sessionKey)
            ?? (self.database == nil ? UserDefaults.standard.stringArray(forKey: Self.sessionKey) : nil)
            ?? []
        let sessionURLs = (savedSession?.urls ?? legacySessionURLs).compactMap(URL.init(string:))
        let selectedIndex = min(savedSession?.selectedIndex ?? sessionURLs.count - 1, sessionURLs.count - 1)
        let savedRecentlyClosed = databaseValue(self.database, [String].self, forKey: Self.recentlyClosedKey) ?? []
        recentlyClosed = savedRecentlyClosed.compactMap(URL.init(string:))
        if databaseValue(self.database, Bool.self, forKey: Self.migrationKey) != true {
            migrateLegacyState(sessionURLs: legacySessionURLs)
        }
        if savedSession == nil {
            persist(BrowserSession(urls: legacySessionURLs, selectedIndex: max(0, selectedIndex)), forKey: Self.sessionStateKey)
        }
        if sessionURLs.isEmpty {
            newTab()
        } else {
            let pinnedSet = Set(savedSession?.pinnedIndices ?? [])
            for (index, url) in sessionURLs.enumerated() {
                let tab = newTab(url: url, select: index == selectedIndex)
                if pinnedSet.contains(index) {
                    tab.isPinned = true
                }
            }
        }
        if !hasMigratedFontToGeist {
            persist(defaultFont, forKey: Self.leanUIFontKey)
            persist(defaultFont, forKey: Self.webPageFontKey)
            persist(true, forKey: "hasMigratedFontToGeistV2")
        }
    }

    var isDarkMode: Bool {
        switch theme {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    static let zenModeLightColor = Color(hex: "#E5E5EA")
    static let zenModeDarkColor = Color(hex: "#18181B")

    var effectiveZenColor: Color {
        isDarkMode ? Self.zenModeDarkColor : Self.zenModeLightColor
    }

    var themeColors: ThemeColors {
        ThemeColors(isDark: isDarkMode)
    }

    var adaptiveTheme: AdaptiveFrameTheme {
        AdaptiveFrameTheme(
            isBorderEnabled: enableWindowBorder,
            frameColor: effectiveZenColor,
            baseThemeColors: themeColors,
            isBaseDark: isDarkMode
        )
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    func toggleTheme() {
        theme = isDarkMode ? .light : .dark
    }

    func openSettings(category: SettingsCategory = .general) {
        selectedSettingsCategory = category
        SettingsWindowManager.shared.close()

        if let existingSettingsTab = tabs.first(where: { $0.isSettingsPage }) {
            switchToTab(id: existingSettingsTab.id)
            return
        }

        if let current = selectedTab, current.url == nil {
            if let settingsURL = URL(string: "lean://settings") {
                current.load(settingsURL)
                return
            }
        }

        newTab(url: URL(string: "lean://settings"), select: true)
    }

    func isToolbarItemShown(_ item: ToolbarItemType) -> Bool {
        shownToolbarItems.contains(item)
    }

    func showToolbarItem(_ item: ToolbarItemType) {
        if let index = hiddenToolbarItems.firstIndex(of: item) {
            hiddenToolbarItems.remove(at: index)
        }
        if !shownToolbarItems.contains(item) {
            shownToolbarItems.append(item)
        }
    }

    func hideToolbarItem(_ item: ToolbarItemType) {
        if let index = shownToolbarItems.firstIndex(of: item) {
            shownToolbarItems.remove(at: index)
        }
        if !hiddenToolbarItems.contains(item) {
            hiddenToolbarItems.append(item)
        }
    }

    func toggleToolbarItem(_ item: ToolbarItemType) {
        if shownToolbarItems.contains(item) {
            hideToolbarItem(item)
        } else {
            showToolbarItem(item)
        }
    }

    func resetToolbarItems() {
        shownToolbarItems = ToolbarItemType.allCases
        hiddenToolbarItems = []
    }

    func moveToolbarItem(withId id: String, toShown: Bool) {
        guard let item = ToolbarItemType(rawValue: id) else { return }
        if toShown {
            showToolbarItem(item)
        } else {
            hideToolbarItem(item)
        }
    }

    func updateAllTabsTheme() {
        let isDark = isDarkMode
        for tab in tabs {
            tab.applyTheme(isDark: isDark)
        }
    }

    func updateAllTabsScrollbarStyle() {
        let style = scrollbarStyle
        for tab in tabs {
            tab.applyScrollbarStyle(style)
        }
    }

    func updateAllTabsSmoothScrolling() {
        let enabled = smoothScrollingEnabled
        for tab in tabs {
            tab.applySmoothScrolling(enabled)
        }
    }

    func updateAllTabsHighFrameRate() {
        if highFrameRatePages {
            FrameRate.fast = true
            for tab in tabs {
                tab.applyHighFrameRate()
            }
        } else {
            FrameRate.fast = false
            FrameRate.restoreChanged()
        }
    }

    func updateAllTabsPeekPreferences() {
        let peeks = peeksLinks
        for tab in tabs {
            tab.peeksLinks = peeks
        }
    }

    func updateAllTabsFonts() {
        for tab in tabs {
            tab.applyPageFont(webPageFont)
        }
    }

    func updateAllTabsAdBlocking() {
        for tab in tabs {
            tab.applyAdBlocking(adBlockingEnabled, excluding: adBlockingExcludedHosts)
        }
    }

    func updateAllTabsPasswordPreferences() {
        for tab in tabs {
            tab.applyPasswordPreferences(
                savePromptsEnabled: passwordSavePromptsEnabled,
                suggestionsEnabled: passwordSuggestionsEnabled
            )
        }
    }

    func updateAllTabsPasskeys() {
        for tab in tabs {
            tab.applyPasskeysPreferences(enabled: passkeysEnabled)
        }
    }

    private func showPictureInPicture(for tab: LeanTab) {
        guard !pictureInPicture.showing, !tab.isSleeping else { return }
        // Automatic float only from places people go to watch: anywhere
        // else a technically-playing video is as likely a muted hero loop
        // or ad as a film, and lifting it yields a blank little window
        // for nothing playing. Mirrors Search's quiet lift.
        guard Players.knows(tab.url) else { return }
        tab.webView.evaluateJavaScript(Isolate.on) { [weak self, weak tab] result, _ in
            DispatchQueue.main.async {
                guard let self, let tab, let dimensions = result as? [String: NSNumber],
                      let width = dimensions["width"]?.doubleValue, width > 0,
                      let height = dimensions["height"]?.doubleValue, height > 0 else { return }
                guard self.selectedID != tab.id else {
                    tab.webView.evaluateJavaScript(Isolate.off, completionHandler: nil)
                    return
                }
                self.pictureInPictureTabID = tab.id
                self.pictureInPicture.onClose = { [weak self] in self?.dismissPictureInPicture() }
                self.pictureInPicture.onReturn = { [weak self] in self?.returnFromPictureInPicture() }
                self.pictureInPicture.onPlayPause = { [weak tab] completion in
                    tab?.webView.evaluateJavaScript(Isolate.toggle) { result, _ in
                        completion((result as? Bool) ?? false)
                    }
                }
                self.pictureInPicture.onSkip = { [weak tab] seconds in
                    tab?.webView.evaluateJavaScript(Isolate.skip(seconds), completionHandler: nil)
                }
                self.pictureInPicture.onSeek = { [weak tab] fraction in
                    tab?.webView.evaluateJavaScript(Isolate.seek(fraction), completionHandler: nil)
                }
                self.pictureInPicture.onProgress = { [weak tab] completion in
                    tab?.webView.evaluateJavaScript(Isolate.where_) { result, _ in
                        guard let values = result as? [NSNumber], values.count >= 2 else { return }
                        let progress = values[0].doubleValue
                        let isPlaying = values[1].boolValue
                        let currentTime = values.count >= 4 ? values[2].doubleValue : 0
                        let duration = values.count >= 4 ? values[3].doubleValue : 0
                        completion(progress, isPlaying, currentTime, duration)
                    }
                }
                self.pictureInPicture.lift(
                    tab.webView,
                    aspectRatio: CGFloat(width / height),
                    title: tab.title,
                    url: tab.url,
                    favicon: tab.favicon
                )
                self.revealPictureInPicture(for: tab)
            }
        }
    }

    /// The lift starts invisible (see PictureInPicture.lift): reveal it
    /// once the isolated layout settles, or after a short fallback so a
    /// page that never settles still shows instead of hanging black.
    private func revealPictureInPicture(for tab: LeanTab) {
        tab.webView.evaluateJavaScript(Isolate.settled) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard (result as? Bool) == true else { return }
                self?.pictureInPicture.reveal()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.pictureInPicture.reveal()
        }
    }

    private func dismissPictureInPicture() {
        guard let id = pictureInPictureTabID else { return }
        pictureInPictureTabID = nil
        pictureInPicture.drop()
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.webView.evaluateJavaScript(Isolate.off, completionHandler: nil)
        objectWillChange.send()
    }

    private func returnFromPictureInPicture() {
        guard let id = pictureInPictureTabID,
              let tab = tabs.first(where: { $0.id == id }) else { return }
        // Land first, synchronously: the stage takes the page back on its
        // next layout (see LeanStageView), so by the time the tab is shown
        // the view is already home. Waiting for the JS round-trip before
        // dropping is what left the tab showing a detached page — blank
        // until the user navigated away and back. Mirrors Search's
        // Browser.land(), where the window closes whatever else is true.
        pictureInPictureTabID = nil
        if pictureInPicture.showing { pictureInPicture.drop() }
        tab.webView.evaluateJavaScript(Isolate.off, completionHandler: nil)
        // And go to the tab, wherever this was asked from: the widget's
        // return arrow must land on the playing tab — bringing the browser
        // forward if it wasn't — not just close the window. A manual
        // selection is already there, so setting it again is a no-op.
        if selectedID != id {
            selectedID = id
        }
        NSApp.activate(ignoringOtherApps: true)
        tab.webView.window?.makeFirstResponder(tab.webView)
        objectWillChange.send()
    }

    private func handleTabSelectionChange(from previous: LeanTab.ID?, to current: LeanTab.ID?) {
        guard previous != current else { return }
        let isReturningToPictureInPictureTab = current == pictureInPictureTabID
        if isReturningToPictureInPictureTab {
            returnFromPictureInPicture()
        }
        if !isReturningToPictureInPictureTab,
           let previous, previous != pictureInPictureTabID,
           let tab = tabs.first(where: { $0.id == previous }) {
            // After this runloop: the selection commit and its SwiftUI
            // update go first, so the new tab's content appears at once
            // instead of waiting behind the lift's JS round-trip. The lift
            // itself still refuses a tab that is selected by then.
            DispatchQueue.main.async { [weak self, weak tab] in
                guard let self, let tab else { return }
                self.showPictureInPicture(for: tab)
            }
        }
        if let previous, tabs.contains(where: { $0.id == previous }) {
            inactiveSince[previous] = Date()
        }
        if let current {
            inactiveSince[current] = nil
            sleepWorkItems[current]?.cancel()
            sleepWorkItems[current] = nil
            sleepWorkTokens[current] = nil
        }
        scheduleAutoSleep()
    }

    private func scheduleAutoSleep() {
        sleepWorkItems.values.forEach { $0.cancel() }
        sleepWorkItems.removeAll()
        sleepWorkTokens.removeAll()
        guard autoSleepTabsEnabled else { return }
        let timeout = TimeInterval(autoSleepAfterMinutes * 60)
        for tab in tabs where tab.id != selectedID {
            let inactiveAt = inactiveSince[tab.id] ?? Date()
            inactiveSince[tab.id] = inactiveAt
            let delay = max(0, timeout - Date().timeIntervalSince(inactiveAt))
            let token = UUID()
            sleepWorkTokens[tab.id] = token
            let work = DispatchWorkItem { [weak self, weak tab] in
                guard let self, let tab, self.sleepWorkTokens[tab.id] == token else { return }
                self.sleepWorkTokens[tab.id] = nil
                self.sleepWorkItems[tab.id] = nil
                self.attemptAutoSleep(tab)
            }
            sleepWorkItems[tab.id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func attemptAutoSleep(_ tab: LeanTab) {
        guard autoSleepTabsEnabled, selectedID != tab.id,
              tab.id != pictureInPictureTabID,
              tabs.contains(where: { $0.id == tab.id }) else { return }
        tab.requestSleep(while: { [weak self, weak tab] in
            guard let self, let tab else { return false }
            return self.autoSleepTabsEnabled && self.selectedID != tab.id
                && self.tabs.contains(where: { $0.id == tab.id })
        }) { [weak self, weak tab] slept in
            guard let self, let tab, !slept else { return }
            self.scheduleSleepRetry(for: tab)
        }
    }

    private func scheduleSleepRetry(for tab: LeanTab) {
        guard autoSleepTabsEnabled, selectedID != tab.id else { return }
        sleepWorkItems[tab.id]?.cancel()
        let token = UUID()
        sleepWorkTokens[tab.id] = token
        let retry = DispatchWorkItem { [weak self, weak tab] in
            guard let self, let tab, self.sleepWorkTokens[tab.id] == token else { return }
            self.sleepWorkTokens[tab.id] = nil
            self.sleepWorkItems[tab.id] = nil
            self.attemptAutoSleep(tab)
        }
        sleepWorkItems[tab.id] = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: retry)
    }

    func sleepTab(_ tab: LeanTab, notifyOnFailure: Bool = false) {
        guard selectedID != tab.id, tabs.contains(where: { $0.id == tab.id }) else { return }
        sleepWorkItems[tab.id]?.cancel()
        sleepWorkItems[tab.id] = nil
        sleepWorkTokens[tab.id] = nil
        tab.requestSleep(while: { [weak self, weak tab] in
            guard let self, let tab else { return false }
            return self.selectedID != tab.id && self.tabs.contains(where: { $0.id == tab.id })
        }) { [weak self, weak tab] slept in
            guard !slept, let self, let tab else { return }
            if notifyOnFailure { NSSound.beep() }
            self.scheduleSleepRetry(for: tab)
        }
    }

    private func configureMemoryPressureHandling() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, self.autoSleepTabsEnabled else { return }
                for tab in self.tabs where tab.id != self.selectedID {
                    self.attemptAutoSleep(tab)
                }
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    func isAdBlockingEnabled(for host: String?) -> Bool {
        SiteBlockingPolicy.shouldBlock(globalEnabled: adBlockingEnabled, host: host, excludedHosts: adBlockingExcludedHosts)
    }

    func setAdBlocking(_ enabled: Bool, for host: String) {
        let normalized = SiteBlockingPolicy.normalizedHost(host)
        guard !normalized.isEmpty else { return }
        if enabled {
            adBlockingExcludedHosts.remove(normalized)
        } else {
            adBlockingExcludedHosts.insert(normalized)
        }
        persist(adBlockingExcludedHosts, forKey: Self.adBlockingExcludedHostsKey)
        updateAllTabsAdBlocking()
    }

    func clearCookiesAndSiteData(completion: @escaping @Sendable () -> Void) {
        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeFetchCache,
        ]
        dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes().subtracting(cacheTypes),
            modifiedSince: .distantPast,
            completionHandler: completion
        )
    }

    func clearWebCache(completion: @escaping @Sendable () -> Void) {
        dataStore.removeData(
            ofTypes: [
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache,
                WKWebsiteDataTypeOfflineWebApplicationCache,
                WKWebsiteDataTypeFetchCache,
            ],
            modifiedSince: .distantPast,
            completionHandler: completion
        )
    }

    var selectedTab: LeanTab? {
        tabs.first { $0.id == selectedID }
    }

    func zoomIn() {
        selectedTab?.zoomIn()
    }

    func zoomOut() {
        selectedTab?.zoomOut()
    }

    func resetZoom() {
        selectedTab?.resetZoom()
    }

    func openURL(_ url: URL) {
        if let tab = selectedTab, tab.url == nil, !tab.isPinned {
            tab.load(url)
        } else {
            newTab(url: url)
        }
    }

    func recordHistory(url: URL, title: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle != "New Tab", !url.absoluteString.hasPrefix("lean://") else { return }
        historyItems.removeAll {
            $0.url == url || ($0.url.host == url.host && $0.title == cleanTitle)
        }
        historyItems.insert(HistoryItem(url: url, title: cleanTitle, timestamp: Date()), at: 0)
        if historyItems.count > 200 {
            historyItems = Array(historyItems.prefix(200))
        }
        saveHistory()
    }

    func importBrowserData(_ preview: BrowserImportPreview) -> (bookmarks: Int, history: Int) {
        var seenURLs = Set(importedBookmarks.map { $0.url.absoluteString })
        let newBookmarks = preview.bookmarks.filter { seenURLs.insert($0.url.absoluteString).inserted }
        importedBookmarks.append(contentsOf: newBookmarks)
        persist(importedBookmarks, forKey: Self.importedBookmarksKey)

        for b in newBookmarks {
            if !bookmarks.contains(where: { $0.url.absoluteString == b.url.absoluteString }) {
                bookmarks.append(BookmarkItem(id: b.id, title: b.title, url: b.url, folder: BookmarkFolder.defaultFolder))
            }
        }
        persist(bookmarks, forKey: Self.bookmarksKey)

        let previousHistoryCount = historyItems.count
        var seenHistory = Set(historyItems.map { $0.url.absoluteString })
        let newHistory = preview.history
            .filter { seenHistory.insert($0.url.absoluteString).inserted }
            .sorted { $0.timestamp > $1.timestamp }
        let capacity = max(0, 200 - historyItems.count)
        historyItems.append(contentsOf: newHistory.prefix(capacity))
        historyItems.sort { $0.timestamp > $1.timestamp }
        saveHistory()
        return (newBookmarks.count, historyItems.count - previousHistoryCount)
    }

    func deleteImportedBookmark(id: ImportedBookmark.ID) {
        importedBookmarks.removeAll { $0.id == id }
        bookmarks.removeAll { $0.id == id }
        persist(importedBookmarks, forKey: Self.importedBookmarksKey)
        persist(bookmarks, forKey: Self.bookmarksKey)
    }

    // MARK: - Bookmarks Management

    func toggleBookmarks() {
        isQuickSettingsPresented = false
        isDownloadsPresented = false
        isExtensionsPresented = false
        isFloatingOmnibarVisible = false
        isInlineURLEditing = false
        isBookmarksPresented.toggle()
    }

    func dismissBookmarks() {
        isBookmarksPresented = false
    }

    func isBookmarked(url: URL?) -> Bool {
        guard let url else { return false }
        let target = url.absoluteString.lowercased()
        return bookmarks.contains { $0.url.absoluteString.lowercased() == target }
    }

    func bookmark(for url: URL?) -> BookmarkItem? {
        guard let url else { return nil }
        let target = url.absoluteString.lowercased()
        return bookmarks.first { $0.url.absoluteString.lowercased() == target }
    }

    func addBookmark(title: String, url: URL, folder: String = BookmarkFolder.defaultFolder) {
        let cleanFolder = folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BookmarkFolder.defaultFolder : folder
        if !bookmarkFolders.contains(cleanFolder) && cleanFolder != BookmarkFolder.allFolder {
            bookmarkFolders.append(cleanFolder)
            persist(bookmarkFolders, forKey: Self.bookmarkFoldersKey)
        }
        if let index = bookmarks.firstIndex(where: { $0.url.absoluteString.lowercased() == url.absoluteString.lowercased() }) {
            bookmarks[index].title = title
            bookmarks[index].folder = cleanFolder
        } else {
            let item = BookmarkItem(title: title.isEmpty ? (url.host ?? url.absoluteString) : title, url: url, folder: cleanFolder)
            bookmarks.insert(item, at: 0)
        }
        persist(bookmarks, forKey: Self.bookmarksKey)
    }

    func toggleBookmarkCurrentTab(folder: String? = nil) {
        if isBookmarkDialogPresented {
            dismissBookmarkDialog()
        } else {
            showBookmarkConfirmationDialogForCurrentTab(folder: folder)
        }
    }

    func showBookmarkConfirmationDialogForCurrentTab(folder: String? = nil) {
        guard let tab = selectedTab, let url = tab.url, !url.absoluteString.hasPrefix("lean://") else { return }
        isQuickSettingsPresented = false
        isDownloadsPresented = false
        isExtensionsPresented = false
        isFloatingOmnibarVisible = false
        isInlineURLEditing = false
        isBookmarksPresented = false

        if let existing = bookmark(for: url) {
            dialogBookmarkTitle = existing.title
            dialogBookmarkFolder = existing.folder
            dialogBookmarkURL = existing.url
        } else {
            let title = tab.title.isEmpty ? (url.host ?? url.absoluteString) : tab.title
            let targetFolder = folder ?? (selectedBookmarkFolder == BookmarkFolder.allFolder ? BookmarkFolder.defaultFolder : selectedBookmarkFolder)
            addBookmark(title: title, url: url, folder: targetFolder)
            dialogBookmarkTitle = title
            dialogBookmarkFolder = targetFolder
            dialogBookmarkURL = url
        }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
            isBookmarkDialogPresented = true
        }
    }

    func saveBookmarkDialog(title: String, folder: String) {
        guard let url = dialogBookmarkURL else {
            withAnimation(.easeOut(duration: 0.12)) {
                isBookmarkDialogPresented = false
            }
            return
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFolder = folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BookmarkFolder.defaultFolder : folder
        addBookmark(title: cleanTitle.isEmpty ? (url.host ?? url.absoluteString) : cleanTitle, url: url, folder: cleanFolder)
        withAnimation(.easeOut(duration: 0.12)) {
            isBookmarkDialogPresented = false
        }
    }

    func removeBookmarkFromDialog() {
        if let url = dialogBookmarkURL, let existing = bookmark(for: url) {
            deleteBookmark(id: existing.id)
        }
        withAnimation(.easeOut(duration: 0.12)) {
            isBookmarkDialogPresented = false
        }
    }

    func dismissBookmarkDialog() {
        if let url = dialogBookmarkURL {
            let cleanTitle = dialogBookmarkTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanFolder = dialogBookmarkFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BookmarkFolder.defaultFolder : dialogBookmarkFolder
            addBookmark(title: cleanTitle.isEmpty ? (url.host ?? url.absoluteString) : cleanTitle, url: url, folder: cleanFolder)
        }
        withAnimation(.easeOut(duration: 0.12)) {
            isBookmarkDialogPresented = false
        }
    }

    func deleteBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        importedBookmarks.removeAll { $0.id == id }
        persist(bookmarks, forKey: Self.bookmarksKey)
        persist(importedBookmarks, forKey: Self.importedBookmarksKey)
    }

    func updateBookmark(id: UUID, title: String, url: URL, folder: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let cleanFolder = folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BookmarkFolder.defaultFolder : folder
        if !bookmarkFolders.contains(cleanFolder) && cleanFolder != BookmarkFolder.allFolder {
            bookmarkFolders.append(cleanFolder)
            persist(bookmarkFolders, forKey: Self.bookmarkFoldersKey)
        }
        bookmarks[index].title = title
        bookmarks[index].url = url
        bookmarks[index].folder = cleanFolder
        persist(bookmarks, forKey: Self.bookmarksKey)
    }

    func moveBookmark(id: UUID, to folder: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let cleanFolder = folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BookmarkFolder.defaultFolder : folder
        if !bookmarkFolders.contains(cleanFolder) && cleanFolder != BookmarkFolder.allFolder {
            bookmarkFolders.append(cleanFolder)
            persist(bookmarkFolders, forKey: Self.bookmarkFoldersKey)
        }
        bookmarks[index].folder = cleanFolder
        persist(bookmarks, forKey: Self.bookmarksKey)
    }

    func addBookmarkFolder(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != BookmarkFolder.allFolder, !bookmarkFolders.contains(trimmed) else { return }
        bookmarkFolders.append(trimmed)
        persist(bookmarkFolders, forKey: Self.bookmarkFoldersKey)
    }

    func deleteBookmarkFolder(_ name: String) {
        guard name != BookmarkFolder.defaultFolder && name != BookmarkFolder.allFolder else { return }
        bookmarkFolders.removeAll { $0 == name }
        // Re-assign bookmarks in deleted folder to defaultFolder
        for index in bookmarks.indices {
            if bookmarks[index].folder == name {
                bookmarks[index].folder = BookmarkFolder.defaultFolder
            }
        }
        persist(bookmarkFolders, forKey: Self.bookmarkFoldersKey)
        persist(bookmarks, forKey: Self.bookmarksKey)
        if selectedBookmarkFolder == name {
            selectedBookmarkFolder = BookmarkFolder.allFolder
        }
    }

    func renameBookmarkFolder(from oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != BookmarkFolder.allFolder, oldName != BookmarkFolder.defaultFolder, oldName != BookmarkFolder.allFolder else { return }
        guard let index = bookmarkFolders.firstIndex(of: oldName) else { return }
        bookmarkFolders[index] = trimmed
        for i in bookmarks.indices {
            if bookmarks[i].folder == oldName {
                bookmarks[i].folder = trimmed
            }
        }
        persist(bookmarkFolders, forKey: Self.bookmarkFoldersKey)
        persist(bookmarks, forKey: Self.bookmarksKey)
        if selectedBookmarkFolder == oldName {
            selectedBookmarkFolder = trimmed
        }
    }

    func deleteHistoryItem(id: UUID) {
        historyItems.removeAll { $0.id == id }
        saveHistory()
    }

    func deleteHistoryItem(url: URL) {
        historyItems.removeAll { $0.url == url }
        saveHistory()
    }

    func clearHistory() {
        historyItems.removeAll()
        saveHistory()
    }

    func cancelDownload(id: UUID) {
        for tab in tabs {
            tab.cancelActiveDownload(id: id)
        }
        downloadManager.cancelDownload(id: id)
    }

    func revealDownload(_ item: DownloadItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.destinationURL])
    }

    func openDownload(_ item: DownloadItem) {
        NSWorkspace.shared.open(item.destinationURL)
    }

    func openHistoryItem(_ item: HistoryItem, inNewTab: Bool = false) {        if inNewTab {
            newTab(url: item.url, select: true)
        } else {
            if let current = selectedTab, current.isSettingsPage || current.url == nil {
                current.load(item.url)
            } else {
                newTab(url: item.url, select: true)
            }
        }
    }

    private func deduplicateHistory() {
        var seen = Set<String>()
        historyItems = historyItems.filter { item in
            let host = item.url.host?.lowercased() ?? ""
            let key = "\(host)|\(item.title.lowercased())"
            return seen.insert(key).inserted
        }
    }

    private func saveHistory() {
        deduplicateHistory()
        persist(historyItems, forKey: Self.historyKey)
    }

    func handleNewTabCommand() {
        if let selected = selectedTab, selected.url != nil {
            if isFloatingOmnibarVisible {
                dismissFloatingOmnibar()
            } else {
                showFloatingOmnibar(mode: .newTab)
            }
        } else {
            floatingOmnibarMode = .newTab
            showNewTabOmnibar()
        }
    }

    func showFloatingOmnibar(mode: FloatingOmnibarMode = .newTab) {
        isInlineURLEditing = false
        floatingOmnibarMode = mode
        isFloatingOmnibarVisible = true
    }

    func showNewTabOmnibar() {
        isNewTabOmnibarFloating = true
        NotificationCenter.default.post(name: .focusAddress, object: nil)
    }

    func saveSession() {
        let persistedTabs = tabs.filter { $0.url != nil }
        let urls = persistedTabs.compactMap { $0.url?.absoluteString }
        let selectedIndex = persistedTabs.firstIndex { $0.id == selectedID } ?? max(0, urls.count - 1)
        let pinnedIndices = persistedTabs.enumerated().compactMap { $0.element.isPinned ? $0.offset : nil }
        persist(BrowserSession(urls: urls, selectedIndex: selectedIndex, pinnedIndices: pinnedIndices), forKey: Self.sessionStateKey)
        persist(recentlyClosed.map(\.absoluteString), forKey: Self.recentlyClosedKey)
    }

    func togglePin(tab: LeanTab) {
        guard tab.url != nil || tab.isPinned else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            tab.isPinned.toggle()
            if let currentIndex = tabs.firstIndex(where: { $0.id == tab.id }) {
                tabs.remove(at: currentIndex)
                if tab.isPinned {
                    let lastPinnedIndex = tabs.lastIndex(where: { $0.isPinned }) ?? -1
                    tabs.insert(tab, at: lastPinnedIndex + 1)
                } else {
                    let firstUnpinnedIndex = tabs.firstIndex(where: { !$0.isPinned }) ?? tabs.count
                    tabs.insert(tab, at: firstUnpinnedIndex)
                }
            }
            saveSession()
        }
    }

    @discardableResult
    func newTab(
        url: URL? = nil,
        select: Bool = true,
        configuration: WKWebViewConfiguration? = nil,
        focusAddress: Bool = true,
        popupOpenerID: LeanTab.ID? = nil
    ) -> LeanTab {
        let tab = createTab(url: url, configuration: configuration, popupOpenerID: popupOpenerID)
        tabs.append(tab)
        if let popupOpenerID, let opener = tabs.first(where: { $0.id == popupOpenerID }) {
            opener.hasActivePopup = true
        }
        if !select { inactiveSince[tab.id] = Date() }
        if select {
            selectedID = tab.id
            isNewTabOmnibarFloating = false
            if url == nil && focusAddress {
                NotificationCenter.default.post(name: .focusAddress, object: nil)
            }
        }
        saveSession()
        scheduleAutoSleep()
        return tab
    }

    func createTab(
        url: URL? = nil,
        configuration: WKWebViewConfiguration? = nil,
        popupOpenerID: LeanTab.ID? = nil
    ) -> LeanTab {
        let tab = LeanTab(
            dataStore: dataStore,
            initialURL: configuration == nil ? url : nil,
            isDark: isDarkMode,
            scrollbarStyle: scrollbarStyle,
            smoothScrolling: smoothScrollingEnabled,
            pageFont: webPageFont,
            adBlockingEnabled: adBlockingEnabled,
            adBlockingExcludedHosts: adBlockingExcludedHosts,
            passwordSavePromptsEnabled: passwordSavePromptsEnabled,
            passwordSuggestionsEnabled: passwordSuggestionsEnabled,
            passkeysEnabled: passkeysEnabled,
            configuration: configuration
        )
        wireTab(tab)
        tab.popupOpenerID = popupOpenerID
        return tab
    }

    private func wireTab(_ tab: LeanTab) {
        tab.onStateChange = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.objectWillChange.send()
            if let tabURL = tab.url, !tab.isLoading {
                self.recordHistory(url: tabURL, title: tab.title)
            }
            self.saveSession()
        }
        tab.downloadManager = downloadManager
        tab.mediaPermissionStore = mediaPermissionStore
        tab.peeksLinks = peeksLinks
        tab.onPeekLink = { [weak self, weak tab] url in
            guard let self, let tab else { return }
            self.peek(url, from: tab)
        }
        tab.onDownloadFailed = { [weak self] in
            guard let self else { return }
            self.isDownloadsPresented = true
        }
        tab.onCloseTab = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.close(tab)
        }
        tab.onOpenNewTab = { [weak self, weak tab] _, configuration in
            guard let self, let tab else { return nil }
            let child = self.newTab(url: nil, configuration: configuration, popupOpenerID: tab.id)
            child.onCloseTab = { [weak self, weak child] in
                guard let self, let child else { return }
                self.close(child)
            }
            return child.webView
        }
        tab.onOpenSourceTab = { [weak self] title, html in
            self?.openPageSource(title: title, html: html)
        }
        tab.onOpenURLInNewTab = { [weak self] url in
            self?.newTab(url: url)
        }
    }

    // MARK: - Split Tab Support

    func select(tab: LeanTab) {
        selectedID = tab.id
        saveSession()
    }

    func openTabAsSplit(_ tab: LeanTab) {
        guard !tab.isSplit else { return }
        if let active = selectedTab, active.id != tab.id {
            if !active.isSplit {
                openTabsAsSplit(active, tab)
            } else if active.splitTabs.count < 4 {
                // Active is already a split: "open as split" on a background
                // tab means joining the existing split, never spawning a
                // stray empty tab.
                addTabToSplit(active, tabToAdd: tab)
            }
            // At max capacity (4 panes): no-op rather than a wrong split.
        } else {
            // Splitting the current tab itself: pair it with an empty pane.
            let companion = createTab(url: nil)
            tab.splitTabs = [tab, companion]
            tab.splitWidthRatios = []
            tab.activeSplitIndex = 1
            select(tab: tab)
            objectWillChange.send()
        }
    }

    /// Combine two existing tabs into a split owned by `active`.
    /// Never creates an empty tab — the background-tab context-menu path
    /// must always end up with `active` + `other`, not `active` + New Tab.
    func openTabsAsSplit(_ active: LeanTab, _ other: LeanTab) {
        guard active.id != other.id, !active.isSplit, !other.isSplit else { return }
        guard tabs.contains(where: { $0.id == active.id }),
              tabs.contains(where: { $0.id == other.id }) else { return }
        tabs.removeAll { $0.id == other.id }
        active.splitTabs = [active, other]
        active.splitWidthRatios = []
        active.activeSplitIndex = 1
        select(tab: active)
        objectWillChange.send()
    }

    func addTabToActiveSplit(_ tabToAdd: LeanTab) {
        guard let active = selectedTab else { return }
        addTabToSplit(active, tabToAdd: tabToAdd)
    }

    /// Add `tabToAdd` to an explicit split parent. The context menus capture
    /// the parent when the menu is built so a selection change between
    /// menu display and tap can't redirect the tab into the wrong split.
    func addTabToSplit(_ active: LeanTab, tabToAdd: LeanTab) {
        guard active.id != tabToAdd.id else { return }
        guard tabs.contains(where: { $0.id == active.id }),
              tabs.contains(where: { $0.id == tabToAdd.id }) else { return }
        if active.isSplit {
            guard active.splitTabs.count < 4 else { return }
            tabs.removeAll { $0.id == tabToAdd.id }
            active.splitTabs.append(tabToAdd)
            active.activeSplitIndex = active.splitTabs.count - 1
        } else {
            tabs.removeAll { $0.id == tabToAdd.id }
            active.splitTabs = [active, tabToAdd]
            active.splitWidthRatios = []
            active.activeSplitIndex = 1
        }
        select(tab: active)
        objectWillChange.send()
    }

    func separateSplitTabs(_ tab: LeanTab) {
        guard tab.isSplit else { return }
        let subTabs = tab.splitTabs
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.splitTabs.removeAll()
        var insertIndex = index + 1
        for other in subTabs where other.id != tab.id {
            other.splitTabs.removeAll()
            tabs.insert(other, at: min(insertIndex, tabs.count))
            insertIndex += 1
        }
        objectWillChange.send()
    }

    /// Close a split pane without closing its tab: the pane leaves the split
    /// and rejoins the row as a standalone tab. When one pane (or none) is
    /// left, the split collapses with the remainder taking the parent's
    /// slot. Nothing here ever destroys a tab.
    func closeSplitPane(in parentTab: LeanTab, pane: LeanTab) {
        guard parentTab.isSplit,
              parentTab.splitTabs.contains(where: { $0.id == pane.id }),
              let parentIndex = tabs.firstIndex(where: { $0.id == parentTab.id }) else { return }
        parentTab.splitTabs.removeAll { $0.id == pane.id }
        pane.splitTabs.removeAll()
        if parentTab.splitTabs.count <= 1 {
            // Collapse: lay the survivors back into the row at the parent's
            // slot — the remainder first, then the closed pane — and select
            // the remainder.
            var survivors = parentTab.splitTabs
            if !survivors.contains(where: { $0.id == parentTab.id }), pane.id != parentTab.id {
                survivors.append(parentTab)
            }
            if !survivors.contains(where: { $0.id == pane.id }) {
                survivors.append(pane)
            }
            parentTab.splitTabs.removeAll()
            for tab in survivors { tab.splitTabs.removeAll() }
            if survivors.isEmpty {
                // Unreachable (a split holds at least two): keep the pane.
                tabs.insert(pane, at: min(parentIndex + 1, tabs.count))
                select(tab: pane)
            } else {
                tabs.replaceSubrange(parentIndex...parentIndex, with: survivors)
                select(tab: survivors[0])
            }
        } else {
            tabs.insert(pane, at: min(parentIndex + 1, tabs.count))
            if parentTab.activeSplitIndex >= parentTab.splitTabs.count {
                parentTab.activeSplitIndex = max(0, parentTab.splitTabs.count - 1)
            }
        }
        saveSession()
        scheduleAutoSleep()
        objectWillChange.send()
    }

    @discardableResult
    func openPageSource(title: String, html: String?) -> LeanTab {
        let tab = newTab(focusAddress: false)
        tab.presentPageSource(title: title, html: html)
        return tab
    }

    func close(_ tab: LeanTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if pictureInPictureTabID == tab.id { dismissPictureInPicture() }
        if let url = tab.url {
            recentlyClosed.append(url)
            recentlyClosed = Array(recentlyClosed.suffix(10))
        }

        sleepWorkItems[tab.id]?.cancel()
        sleepWorkItems[tab.id] = nil
        sleepWorkTokens[tab.id] = nil
        inactiveSince[tab.id] = nil
        let wasSelected = selectedID == tab.id
        let closedTab = tabs.remove(at: index)
        if let openerID = closedTab.popupOpenerID,
           let opener = tabs.first(where: { $0.id == openerID }) {
            opener.hasActivePopup = tabs.contains { $0.popupOpenerID == openerID }
        }
        closedTab.destroy()

        if tabs.isEmpty {
            newTab()
        } else if wasSelected {
            selectedID = tabs[min(index, tabs.count - 1)].id
            isNewTabOmnibarFloating = false
            isInlineURLEditing = false
            inlineURLBarFrame = .zero
            inlineSuggestionsFrame = .zero
        }
        saveSession()
        scheduleAutoSleep()
    }

    func closeSelectedTab() {
        if peekTab != nil {
            closePeek()
            return
        }
        guard let selectedTab else { return }
        close(selectedTab)
    }

    // MARK: - Link peek

    /// Shift-click on a link, from a tab in the row: its page opens over
    /// this one, which stays where it was underneath. One at a time.
    func peek(_ url: URL, from tab: LeanTab) {
        guard peekTab == nil, tabs.contains(where: { $0.id == tab.id }) else { return }
        let page = createTab(url: url)
        page.isPeekTab = true
        page.peeksLinks = false
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { peekTab = page }
    }

    /// Put away: the page goes with the panel.
    func closePeek() {
        guard let page = peekTab else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) { peekTab = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            page.destroy()
        }
    }

    /// Kept: a tab beside the one it was opened from, and in front — loaded
    /// as it is, nothing loaded twice.
    func keepPeek() {
        guard let page = peekTab else { return }
        let here = tabs.firstIndex { $0.id == selectedID }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) { peekTab = nil }
        page.isPeekTab = false
        page.peeksLinks = peeksLinks
        insert(page, at: here.map { $0 + 1 } ?? tabs.count)
        selectedID = page.id
        saveSession()
        scheduleAutoSleep()
    }

    /// A tab made outside the row — a peek being kept — put in it at `index`.
    func insert(_ tab: LeanTab, at index: Int) {
        tabs.insert(tab, at: min(max(0, index), tabs.count))
        saveSession()
    }

    func reopenClosedTab() {
        guard let url = recentlyClosed.popLast() else { return }
        newTab(url: url)
    }

    func dismissFloatingOmnibar() {
        isFloatingOmnibarVisible = false
        floatingPaletteFrame = .zero
        DispatchQueue.main.async { [weak self] in
            guard let self, let tab = self.selectedTab, tab.hasWebView else { return }
            tab.webView.window?.makeFirstResponder(tab.webView)
        }
    }

    func dismissNewTabOmnibar() {
        withAnimation(.easeOut(duration: 0.16)) {
            isNewTabOmnibarFloating = false
        }
    }

    func dismissInlineURLEditing() {
        guard isInlineURLEditing else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            isInlineURLEditing = false
        }
        inlineURLBarFrame = .zero
        inlineSuggestionsFrame = .zero
        DispatchQueue.main.async { [weak self] in
            guard let self, let tab = self.selectedTab, tab.hasWebView else { return }
            tab.webView.evaluateJavaScript("window.getSelection()?.removeAllRanges()", completionHandler: nil)
            tab.webView.window?.makeFirstResponder(tab.webView)
        }
    }

    func switchToTab(id: LeanTab.ID) {
        if pictureInPictureTabID == id {
            returnFromPictureInPicture()
            return
        }
        isFloatingOmnibarVisible = false
        isNewTabOmnibarFloating = false
        isInlineURLEditing = false
        inlineURLBarFrame = .zero
        inlineSuggestionsFrame = .zero
        floatingPaletteFrame = .zero
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            selectedID = id
        }
        saveSession()
        DispatchQueue.main.async { [weak self] in
            guard let self, let tab = self.selectedTab, tab.hasWebView else { return }
            tab.webView.window?.makeFirstResponder(tab.webView)
        }
    }

    func selectNextTab(reverse: Bool = false) {
        guard tabs.count > 1,
              let selectedID,
              let index = tabs.firstIndex(where: { $0.id == selectedID }) else { return }
        let offset = reverse ? tabs.count - 1 : 1
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            self.selectedID = tabs[(index + offset) % tabs.count].id
        }
        saveSession()
        DispatchQueue.main.async { [weak self] in
            guard let self, let tab = self.selectedTab, tab.hasWebView else { return }
            tab.webView.window?.makeFirstResponder(tab.webView)
        }
    }

    func moveTab(id: LeanTab.ID, toIndex destination: Int) {
        guard let source = tabs.firstIndex(where: { $0.id == id }), tabs.count > 1 else { return }
        var reordered = tabs
        let tab = reordered.remove(at: source)

        let targetIndex: Int
        if tab.isPinned {
            let pinnedCount = reordered.filter(\.isPinned).count
            targetIndex = min(max(destination, 0), pinnedCount)
        } else {
            let pinnedCount = reordered.filter(\.isPinned).count
            targetIndex = min(max(destination, pinnedCount), reordered.count)
        }

        reordered.insert(tab, at: targetIndex)
        guard reordered.map(\.id) != tabs.map(\.id) else { return }
        tabs = reordered
        saveSession()
    }

    func selectTab(number: Int) {
        guard !tabs.isEmpty else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            selectedID = tabs[index].id
        }
        saveSession()
    }

    // MARK: - Ctrl+Tab Switcher Navigation

    var switcherTabs: [LeanTab] {
        // Exclude empty/new tabs from switcher; if all are empty, fall back to current tabs
        let loaded = tabs.filter { $0.url != nil }
        return loaded.isEmpty ? tabs : loaded
    }

    func startTabSwitcher(reverse: Bool = false) {
        let validTabs = switcherTabs
        guard !validTabs.isEmpty else { return }

        // If thumbnail previews are enabled, capture snapshot asynchronously in background so switcher opens with 0ms lag
        if enableThumbnailsInTabSwitcher, selectedTab?.snapshot == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectedTab?.snapshot == nil else { return }
                self.selectedTab?.captureSnapshot()
            }
        }

        if !isTabSwitcherVisible {
            isTabSwitcherVisible = true
            let currentIndex = validTabs.firstIndex(where: { $0.id == selectedID }) ?? 0
            let offset = reverse ? validTabs.count - 1 : 1
            switcherSelectedIndex = (currentIndex + offset) % validTabs.count
        } else {
            cycleTabSwitcher(reverse: reverse)
        }
    }

    func cycleTabSwitcher(reverse: Bool = false) {
        let validTabs = switcherTabs
        guard !validTabs.isEmpty else { return }
        let offset = reverse ? validTabs.count - 1 : 1
        switcherSelectedIndex = (switcherSelectedIndex + offset) % validTabs.count
    }

    func commitTabSwitcher() {
        guard isTabSwitcherVisible else { return }
        isTabSwitcherVisible = false
        let validTabs = switcherTabs
        if validTabs.indices.contains(switcherSelectedIndex) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                selectedID = validTabs[switcherSelectedIndex].id
            }
            saveSession()
        }
    }

    func cancelTabSwitcher() {
        isTabSwitcherVisible = false
    }

    // MARK: - Custom Shortcuts
    func shortcut(for action: ShortcutAction) -> CustomKeyCombo {
        customShortcuts[action.rawValue] ?? action.defaultShortcut
    }

    func setShortcut(_ combo: CustomKeyCombo, for action: ShortcutAction) {
        customShortcuts[action.rawValue] = combo
    }

    func resetShortcut(for action: ShortcutAction) {
        customShortcuts.removeValue(forKey: action.rawValue)
    }

    func resetAllShortcuts() {
        customShortcuts.removeAll()
    }

    func isCustomized(_ action: ShortcutAction) -> Bool {
        customShortcuts[action.rawValue] != nil
    }

    private func saveCustomShortcuts() {
        persist(customShortcuts, forKey: Self.customShortcutsKey)
    }

    private func loadCustomShortcuts() {
        if let loaded = databaseValue(database, [String: CustomKeyCombo].self, forKey: Self.customShortcutsKey) {
            customShortcuts = loaded
        } else if let data = UserDefaults.standard.data(forKey: Self.customShortcutsKey),
                  let loaded = try? JSONDecoder().decode([String: CustomKeyCombo].self, from: data) {
            customShortcuts = loaded
        }
    }

    private func migrateLegacyState(sessionURLs: [String]) {
        persist(searchEngine.rawValue, forKey: Self.searchEngineKey)
        persist(adBlockingEnabled, forKey: Self.adBlockingKey)
        persist(theme.rawValue, forKey: Self.themeKey)
        persist(scrollbarStyle.rawValue, forKey: Self.scrollbarKey)
        persist(tabDisplayMode.rawValue, forKey: Self.tabDisplayModeKey)
        persist(tabLayout.rawValue, forKey: Self.tabLayoutKey)
        persist(isSidebarCollapsed, forKey: Self.isSidebarCollapsedKey)
        persist(enableThumbnailsInTabSwitcher, forKey: Self.thumbnailsSwitcherKey)
        persist(smoothScrollingEnabled, forKey: Self.smoothScrollingKey)
        persist(themedTabBar, forKey: Self.themedTabBarKey)
        persist(peeksLinks, forKey: Self.peeksLinksKey)
        persist(showFullTitleOnActiveTab, forKey: Self.showFullTitleKey)
        persist(leanUIFont.rawValue, forKey: Self.leanUIFontKey)
        persist(uiHeadingWeight.rawValue, forKey: Self.uiHeadingWeightKey)
        persist(uiBodyWeight.rawValue, forKey: Self.uiBodyWeightKey)
        persist(browserUIScalePercent, forKey: Self.browserUIScaleKey)
        persist(webPageFont.rawValue, forKey: Self.webPageFontKey)
        persist(enableZenMode, forKey: Self.zenModeKey)
        persist(enableWindowBorder, forKey: Self.windowBorderKey)
        persist(windowBorderColor.toHex(), forKey: Self.windowBorderColorKey)
        persist(Double(windowBorderWidth), forKey: Self.windowBorderWidthKey)
        persist(shownToolbarItems.map(\.rawValue), forKey: Self.shownToolbarItemsKey)
        persist(hiddenToolbarItems.map(\.rawValue), forKey: Self.hiddenToolbarItemsKey)
        persist(historyItems, forKey: Self.historyKey)
        persist(customShortcuts, forKey: Self.customShortcutsKey)
        persist(sessionURLs, forKey: Self.sessionKey)
        persist(true, forKey: Self.migrationKey)
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        guard let database else { return }
        if case .failure(let error) = database.set(value, forKey: key) {
            NSLog("Could not persist %@: %@", key, String(describing: error))
        }
    }

    private static let migrationKey = "sqliteMigration_v1"
    private static let sessionKey = "sessionURLs"
    private static let sessionStateKey = "browserSession_v1"
    private static let recentlyClosedKey = "recentlyClosedURLs"
    private static let historyKey = "visitedHistory"
    private static let importedBookmarksKey = "importedBookmarks_v1"
    private static let bookmarksKey = "bookmarks_v1"
    private static let bookmarkFoldersKey = "bookmarkFolders_v1"
    private static let searchEngineKey = "searchEngine"
    private static let adBlockingKey = "adBlockingEnabled"
    private static let passwordSavePromptsKey = "passwordSavePromptsEnabled"
    private static let passwordSuggestionsKey = "passwordSuggestionsEnabled"
    private static let passkeysEnabledKey = "passkeysEnabled"
    private static let autoSleepTabsEnabledKey = "autoSleepTabsEnabled"
    private static let autoSleepAfterMinutesKey = "autoSleepAfterMinutes"
    private static let adBlockingExcludedHostsKey = "adBlockingExcludedHosts_v1"
    private static let themeKey = "appTheme"
    private static let scrollbarKey = "scrollbarStyle"
    private static let tabDisplayModeKey = "tabDisplayMode"
    private static let tabLayoutKey = "tabLayout"
    private static let isSidebarCollapsedKey = "isSidebarCollapsed"
    private static let thumbnailsSwitcherKey = "enableThumbnailsInTabSwitcher"
    private static let smoothScrollingKey = "smoothScrollingEnabled"
    private static let peeksLinksKey = "links.peek"
    private static let themedTabBarKey = "themedTabBar"
    private static let highFrameRatePagesKey = "highFrameRatePages"
    private static let showFullTitleKey = "showFullTitleOnActiveTab"
    private static let leanUIFontKey = "leanUIFont"
    private static let uiHeadingWeightKey = "uiHeadingWeight"
    private static let uiBodyWeightKey = "uiBodyWeight"
    private static let browserUIScaleKey = "browserUIScalePercent"
    private static let webPageFontKey = "webPageFont"
    private static let zenModeKey = "enableZenMode"
    private static let windowBorderKey = "enableWindowBorder"
    private static let windowBorderColorKey = "windowBorderColor"
    private static let windowBorderWidthKey = "windowBorderWidth"
    private static let shownToolbarItemsKey = "shownToolbarItems"
    private static let hiddenToolbarItemsKey = "hiddenToolbarItems"
    private static let customShortcutsKey = "customShortcuts_v1"
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
}

private func databaseValue<T: Decodable>(
    _ database: AppDatabase?,
    _ type: T.Type,
    forKey key: String
) -> T? {
    guard let database else { return nil }
    switch database.value(type, forKey: key) {
    case .success(let value):
        return value
    case .failure(let error):
        NSLog("Could not read %@: %@", key, String(describing: error))
        return nil
    }
}
