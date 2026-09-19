import AppKit
import Combine
import Foundation
import SwiftUI
import WebKit

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
        case .hybrid: return "Icon & title"
        }
    }
}

enum ToolbarItemType: String, CaseIterable, Identifiable, Codable, Equatable, Hashable {
    case back = "back"
    case forward = "forward"
    case reload = "reload"
    case newTab = "newTab"
    case themeToggle = "themeToggle"
    case settings = "settings"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .back: return "Back"
        case .forward: return "Forward"
        case .reload: return "Reload"
        case .newTab: return "New Tab"
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
        case .themeToggle: return "sun.max.fill"
        case .settings: return "gearshape"
        }
    }

    var isNavigationItem: Bool {
        switch self {
        case .back, .forward, .reload:
            return true
        case .newTab, .themeToggle, .settings:
            return false
        }
    }
}

struct HistoryItem: Identifiable, Equatable, Hashable {
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
    @Published var selectedID: LeanTab.ID?
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
    var visitedHistory: [(url: URL, title: String)] {
        historyItems.map { ($0.url, $0.title) }
    }

    @Published var searchEngine: SearchEngine {
        didSet {
            UserDefaults.standard.set(searchEngine.rawValue, forKey: Self.searchEngineKey)
        }
    }

    @Published var adBlockingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(adBlockingEnabled, forKey: Self.adBlockingKey)
            updateAllTabsAdBlocking()
        }
    }

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
            updateAllTabsTheme()
        }
    }

    @Published var scrollbarStyle: ScrollbarStyle {
        didSet {
            UserDefaults.standard.set(scrollbarStyle.rawValue, forKey: Self.scrollbarKey)
            updateAllTabsScrollbarStyle()
        }
    }

    @Published var tabDisplayMode: TabDisplayMode {
        didSet {
            UserDefaults.standard.set(tabDisplayMode.rawValue, forKey: Self.tabDisplayModeKey)
        }
    }

    @Published var enableThumbnailsInTabSwitcher: Bool {
        didSet {
            UserDefaults.standard.set(enableThumbnailsInTabSwitcher, forKey: Self.thumbnailsSwitcherKey)
        }
    }

    @Published var smoothScrollingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smoothScrollingEnabled, forKey: Self.smoothScrollingKey)
            updateAllTabsSmoothScrolling()
        }
    }

    @Published var showFullTitleOnActiveTab: Bool {
        didSet {
            UserDefaults.standard.set(showFullTitleOnActiveTab, forKey: Self.showFullTitleKey)
        }
    }

    @Published var leanUIFont: LeanFont {
        didSet {
            UserDefaults.standard.set(leanUIFont.rawValue, forKey: Self.leanUIFontKey)
        }
    }

    @Published var webPageFont: LeanFont {
        didSet {
            UserDefaults.standard.set(webPageFont.rawValue, forKey: Self.webPageFontKey)
            updateAllTabsFonts()
        }
    }

    @Published var enableZenMode: Bool {
        didSet {
            UserDefaults.standard.set(enableZenMode, forKey: Self.zenModeKey)
        }
    }

    @Published var enableWindowBorder: Bool {
        didSet {
            UserDefaults.standard.set(enableWindowBorder, forKey: Self.windowBorderKey)
        }
    }

    @Published var windowBorderColor: Color {
        didSet {
            UserDefaults.standard.set(windowBorderColor.toHex(), forKey: Self.windowBorderColorKey)
        }
    }

    @Published var windowBorderWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(windowBorderWidth, forKey: Self.windowBorderWidthKey)
        }
    }

    @Published var shownToolbarItems: [ToolbarItemType] {
        didSet {
            UserDefaults.standard.set(shownToolbarItems.map(\.rawValue), forKey: Self.shownToolbarItemsKey)
        }
    }

    @Published var hiddenToolbarItems: [ToolbarItemType] {
        didSet {
            UserDefaults.standard.set(hiddenToolbarItems.map(\.rawValue), forKey: Self.hiddenToolbarItemsKey)
        }
    }

    private let dataStore: WKWebsiteDataStore
    private var recentlyClosed: [URL] = []

    init(dataStore: WKWebsiteDataStore? = nil) {
        self.dataStore = dataStore ?? WKWebsiteDataStore.default()

        let savedSearchEngine = UserDefaults.standard.string(forKey: Self.searchEngineKey) ?? SearchEngine.google.rawValue
        self.searchEngine = SearchEngine(rawValue: savedSearchEngine) ?? .google

        let savedAdBlocking = UserDefaults.standard.object(forKey: Self.adBlockingKey) as? Bool ?? true
        self.adBlockingEnabled = savedAdBlocking

        if let savedHistory = UserDefaults.standard.array(forKey: Self.historyKey) as? [[String: Any]] {
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

        // Load saved theme (default to light or saved preference)
        let savedTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? AppTheme.light.rawValue
        self.theme = AppTheme(rawValue: savedTheme) ?? .light

        // Load saved scrollbar style (default to normal)
        let savedScrollbar = UserDefaults.standard.string(forKey: Self.scrollbarKey) ?? ScrollbarStyle.normal.rawValue
        self.scrollbarStyle = ScrollbarStyle(rawValue: savedScrollbar) ?? .normal

        // Load saved tab display mode (default to textOnly)
        let savedTabDisplay = UserDefaults.standard.string(forKey: Self.tabDisplayModeKey) ?? TabDisplayMode.textOnly.rawValue
        self.tabDisplayMode = TabDisplayMode(rawValue: savedTabDisplay) ?? .textOnly

        // Load saved tab switcher thumbnail preference (default to true)
        let savedThumbnails = UserDefaults.standard.object(forKey: Self.thumbnailsSwitcherKey) as? Bool ?? true
        self.enableThumbnailsInTabSwitcher = savedThumbnails

        // Load saved smooth scrolling preference (default to true)
        let savedSmoothScrolling = UserDefaults.standard.object(forKey: Self.smoothScrollingKey) as? Bool ?? true
        self.smoothScrollingEnabled = savedSmoothScrolling

        // Load saved show full title preference (default to true)
        let savedShowFullTitle = UserDefaults.standard.object(forKey: Self.showFullTitleKey) as? Bool ?? true
        self.showFullTitleOnActiveTab = savedShowFullTitle

        let savedLeanUIFont = UserDefaults.standard.string(forKey: Self.leanUIFontKey) ?? LeanFont.system.rawValue
        self.leanUIFont = LeanFont(rawValue: savedLeanUIFont) ?? .system

        let savedWebPageFont = UserDefaults.standard.string(forKey: Self.webPageFontKey) ?? LeanFont.system.rawValue
        self.webPageFont = LeanFont(rawValue: savedWebPageFont) ?? .system

        let savedZen = UserDefaults.standard.object(forKey: Self.zenModeKey) as? Bool ?? false
        self.enableZenMode = savedZen

        let savedBorder = UserDefaults.standard.object(forKey: Self.windowBorderKey) as? Bool ?? false
        self.enableWindowBorder = savedBorder

        let savedBorderHex = UserDefaults.standard.string(forKey: Self.windowBorderColorKey) ?? "#2C2D32"
        self.windowBorderColor = Color(hex: savedBorderHex)

        let savedBorderWidth = UserDefaults.standard.object(forKey: Self.windowBorderWidthKey) as? CGFloat ?? 8.0
        self.windowBorderWidth = savedBorderWidth

        // Load saved toolbar items (default to all shown, none hidden)
        let savedShown = UserDefaults.standard.stringArray(forKey: Self.shownToolbarItemsKey)
        let savedHidden = UserDefaults.standard.stringArray(forKey: Self.hiddenToolbarItemsKey)
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

        deduplicateHistory()
        saveHistory()

        let savedSession = UserDefaults.standard.stringArray(forKey: Self.sessionKey) ?? []
        let sessionURLs = savedSession.compactMap(URL.init(string:))
        if sessionURLs.isEmpty {
            newTab()
        } else {
            for (index, url) in sessionURLs.enumerated() {
                newTab(url: url, select: index == sessionURLs.count - 1)
            }
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

    func openSettings() {
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

    func updateAllTabsFonts() {
        for tab in tabs {
            tab.applyPageFont(webPageFont)
        }
    }

    func updateAllTabsAdBlocking() {
        for tab in tabs {
            tab.applyAdBlocking(adBlockingEnabled)
        }
    }

    var selectedTab: LeanTab? {
        tabs.first { $0.id == selectedID }
    }

    func openURL(_ url: URL) {
        if let tab = selectedTab, tab.url == nil {
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

    func openHistoryItem(_ item: HistoryItem, inNewTab: Bool = false) {
        if inNewTab {
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
        let history: [[String: Any]] = historyItems.map {
            [
                "url": $0.url.absoluteString,
                "title": $0.title,
                "timestamp": $0.timestamp.timeIntervalSince1970
            ]
        }
        UserDefaults.standard.set(history, forKey: Self.historyKey)
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
        let urls = tabs.compactMap { $0.url?.absoluteString }
        UserDefaults.standard.set(urls, forKey: Self.sessionKey)
    }

    func newTab(url: URL? = nil, select: Bool = true) {
        let tab = LeanTab(
            dataStore: dataStore,
            initialURL: url,
            isDark: isDarkMode,
            scrollbarStyle: scrollbarStyle,
            smoothScrolling: smoothScrollingEnabled,
            pageFont: webPageFont,
            adBlockingEnabled: adBlockingEnabled
        )
        tab.onStateChange = { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            if let tabURL = tab.url, !tab.isLoading {
                self.recordHistory(url: tabURL, title: tab.title)
            }
            self.saveSession()
        }
        tab.onOpenNewTab = { [weak self] url in self?.newTab(url: url) }
        tabs.append(tab)
        if select {
            selectedID = tab.id
            isNewTabOmnibarFloating = false
            if url == nil {
                NotificationCenter.default.post(name: .focusAddress, object: nil)
            }
        }
        saveSession()
    }

    func close(_ tab: LeanTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if let url = tab.url {
            recentlyClosed.append(url)
            recentlyClosed = Array(recentlyClosed.suffix(10))
        }

        let wasSelected = selectedID == tab.id
        let closedTab = tabs.remove(at: index)
        closedTab.destroy()
        saveSession()

        if tabs.isEmpty {
            newTab()
        } else if wasSelected {
            selectedID = tabs[min(index, tabs.count - 1)].id
            isNewTabOmnibarFloating = false
            isInlineURLEditing = false
            inlineURLBarFrame = .zero
            inlineSuggestionsFrame = .zero
        }
    }

    func closeSelectedTab() {
        guard let selectedTab else { return }
        close(selectedTab)
    }

    func reopenClosedTab() {
        guard let url = recentlyClosed.popLast() else { return }
        newTab(url: url)
    }

    func dismissFloatingOmnibar() {
        isFloatingOmnibarVisible = false
        floatingPaletteFrame = .zero
        DispatchQueue.main.async { [weak self] in
            guard let self, let tab = self.selectedTab else { return }
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
            guard let self, let tab = self.selectedTab else { return }
            tab.webView.evaluateJavaScript("window.getSelection()?.removeAllRanges()", completionHandler: nil)
            tab.webView.window?.makeFirstResponder(tab.webView)
        }
    }

    func switchToTab(id: LeanTab.ID) {
        isFloatingOmnibarVisible = false
        isNewTabOmnibarFloating = false
        isInlineURLEditing = false
        inlineURLBarFrame = .zero
        inlineSuggestionsFrame = .zero
        floatingPaletteFrame = .zero
        selectedID = id
        DispatchQueue.main.async { [weak self] in
            guard let self, let tab = self.selectedTab else { return }
            tab.webView.window?.makeFirstResponder(tab.webView)
        }
    }

    func selectNextTab(reverse: Bool = false) {
        guard tabs.count > 1,
              let selectedID,
              let index = tabs.firstIndex(where: { $0.id == selectedID }) else { return }
        let offset = reverse ? tabs.count - 1 : 1
        self.selectedID = tabs[(index + offset) % tabs.count].id
        DispatchQueue.main.async { [weak self] in
            guard let self, let tab = self.selectedTab else { return }
            tab.webView.window?.makeFirstResponder(tab.webView)
        }
    }

    func selectTab(number: Int) {
        guard !tabs.isEmpty else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        selectedID = tabs[index].id
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
        if enableThumbnailsInTabSwitcher {
            DispatchQueue.main.async { [weak self] in
                self?.selectedTab?.captureSnapshot()
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
            selectedID = validTabs[switcherSelectedIndex].id
        }
    }

    func cancelTabSwitcher() {
        isTabSwitcherVisible = false
    }

    private static let sessionKey = "sessionURLs"
    private static let historyKey = "visitedHistory"
    private static let searchEngineKey = "searchEngine"
    private static let adBlockingKey = "adBlockingEnabled"
    private static let themeKey = "appTheme"
    private static let scrollbarKey = "scrollbarStyle"
    private static let tabDisplayModeKey = "tabDisplayMode"
    private static let thumbnailsSwitcherKey = "enableThumbnailsInTabSwitcher"
    private static let smoothScrollingKey = "smoothScrollingEnabled"
    private static let showFullTitleKey = "showFullTitleOnActiveTab"
    private static let leanUIFontKey = "leanUIFont"
    private static let webPageFontKey = "webPageFont"
    private static let zenModeKey = "enableZenMode"
    private static let windowBorderKey = "enableWindowBorder"
    private static let windowBorderColorKey = "windowBorderColor"
    private static let windowBorderWidthKey = "windowBorderWidth"
    private static let shownToolbarItemsKey = "shownToolbarItems"
    private static let hiddenToolbarItemsKey = "hiddenToolbarItems"
}
