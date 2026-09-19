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

@MainActor
final class LeanStore: ObservableObject {
    @Published private(set) var tabs: [LeanTab] = []
    @Published var selectedID: LeanTab.ID?
    @Published var showsFindBar = false
    @Published var isFloatingOmnibarVisible = false
    @Published var floatingOmnibarMode: FloatingOmnibarMode = .newTab
    @Published var isNewTabOmnibarFloating = false
    @Published var showsSettings = false
    @Published var floatingPaletteFrame: CGRect = .zero
    @Published var isTabSwitcherVisible = false
    @Published var switcherSelectedIndex = 0
    @Published var visitedHistory: [(url: URL, title: String)] = []

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

    private let dataStore: WKWebsiteDataStore
    private var recentlyClosed: [URL] = []

    init(dataStore: WKWebsiteDataStore? = nil) {
        self.dataStore = dataStore ?? WKWebsiteDataStore.default()

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

        // Clear any old session tabs so we never have unwanted default tabs on startup!
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)

        // Always start clean with exactly 1 New Tab
        newTab()
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

    var themeColors: ThemeColors {
        ThemeColors(isDark: isDarkMode)
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
        SettingsWindowManager.shared.show(store: self)
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
        guard !cleanTitle.isEmpty, cleanTitle != "New Tab" else { return }
        visitedHistory.removeAll { $0.url == url }
        visitedHistory.insert((url: url, title: cleanTitle), at: 0)
        if visitedHistory.count > 50 {
            visitedHistory = Array(visitedHistory.prefix(50))
        }
    }

    func clearHistory() {
        visitedHistory.removeAll()
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
        floatingOmnibarMode = mode
        isFloatingOmnibarVisible = true
    }

    func showNewTabOmnibar() {
        isNewTabOmnibarFloating = true
        NotificationCenter.default.post(name: .focusAddress, object: nil)
    }

    func newTab(url: URL? = nil, select: Bool = true) {
        let tab = LeanTab(
            dataStore: dataStore,
            initialURL: url,
            isDark: isDarkMode,
            scrollbarStyle: scrollbarStyle,
            smoothScrolling: smoothScrollingEnabled,
            pageFont: webPageFont
        )
        tab.onStateChange = { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            if let tabURL = tab.url, !tab.isLoading {
                self.recordHistory(url: tabURL, title: tab.title)
            }
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

        if tabs.isEmpty {
            newTab()
        } else if wasSelected {
            selectedID = tabs[min(index, tabs.count - 1)].id
            isNewTabOmnibarFloating = false
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

    func switchToTab(id: LeanTab.ID) {
        isFloatingOmnibarVisible = false
        isNewTabOmnibarFloating = false
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
    private static let themeKey = "appTheme"
    private static let scrollbarKey = "scrollbarStyle"
    private static let tabDisplayModeKey = "tabDisplayMode"
    private static let thumbnailsSwitcherKey = "enableThumbnailsInTabSwitcher"
    private static let smoothScrollingKey = "smoothScrollingEnabled"
    private static let showFullTitleKey = "showFullTitleOnActiveTab"
    private static let leanUIFontKey = "leanUIFont"
    private static let webPageFontKey = "webPageFont"
}
