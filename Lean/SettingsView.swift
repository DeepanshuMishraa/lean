import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case topBar = "Top Bar"
    case appearance = "Appearance"
    case tabs = "Tabs"
    case browsing = "Browsing"
    case privacy = "Privacy"
    case shortcuts = "Shortcuts"
    case history = "History"
    case downloads = "Downloads"
    case importData = "Import Data"
    case passwords = "Passwords"
    case extensions = "Extensions"

    var id: String { rawValue }

    var icon: Ph {
        switch self {
        case .general: return .slidersHorizontal
        case .topBar: return .layout
        case .appearance: return .palette
        case .tabs: return .tabs
        case .browsing: return .compass
        case .privacy: return .shield
        case .shortcuts: return .command
        case .history: return .clock
        case .downloads: return .arrowCircleDown
        case .importData: return .arrowCircleDown
        case .passwords: return .shield
        case .extensions: return .extension
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Distraction-free focus and window framing"
        case .topBar: return "Customize navigation bar buttons and layout"
        case .appearance: return "Color themes and interface typography"
        case .tabs: return "Tab strip presentation and switcher previews"
        case .browsing: return "Scrollbar styling and scrolling mechanics"
        case .privacy: return "Search provider, content filtering, and local data"
        case .shortcuts: return "Keyboard shortcuts, navigation hotkeys, and quick actions"
        case .history: return "Recently visited pages"
        case .downloads: return "Download location and file history"
        case .importData: return "Bring bookmarks, history, and passwords into Lean"
        case .passwords: return "Manage Keychain sign-ins and password prompts"
        case .extensions: return "Install and manage local browser extensions"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: LeanStore
    @ObservedObject var updater: AppUpdater
    @State private var selectedCategory: SettingsCategory = .general
    @StateObject private var dropdownState = DropdownMenuState()

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 640

            if isCompact {
                // Compact Layout: Top pill category switcher
                VStack(spacing: 0) {
                    compactCategoryBar
                    Divider()
                        .background(dividerColor)

                    ScrollView(.vertical, showsIndicators: false) {
                        contentForSelectedCategory
                            .padding(.horizontal, 24)
                            .padding(.vertical, 28)
                            .frame(maxWidth: .infinity)
                    }
                }
                .background(contentBackground)
            } else {
                // Desktop Layout: Clean Master-Detail Sidebar + Detail Pane
                HStack(spacing: 0) {
                    sidebarView
                        .frame(width: 210)
                        .background(sidebarBackground)

                    Rectangle()
                        .fill(dividerColor)
                        .frame(width: 0.75)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            categoryHeader

                            contentForSelectedCategory
                        }
                        .frame(maxWidth: 580)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(contentBackground)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(dropdownState)
        .environment(\.leanSettingsFont, store.leanUIFont)
        .preferredColorScheme(store.colorScheme)
        .onAppear {
            selectedCategory = store.selectedSettingsCategory
        }
        .onChange(of: store.selectedSettingsCategory) { _, newCat in
            if selectedCategory != newCat {
                selectedCategory = newCat
            }
        }
        .onChange(of: selectedCategory) { _, newCat in
            store.selectedSettingsCategory = newCat
            dropdownState.dismiss()
        }
    }

    // MARK: - Color Tokens
    private var sidebarBackground: Color {
        store.isDarkMode ? Color(white: 0.04) : Color(white: 0.975)
    }

    private var contentBackground: Color {
        store.themeColors.windowBackground
    }

    private var dividerColor: Color {
        store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }

    private var primaryText: Color {
        store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12)
    }

    private var secondaryText: Color {
        store.isDarkMode ? Color(white: 0.50) : Color(white: 0.48)
    }

    // MARK: - Sidebar View
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Settings Title
            HStack(spacing: 10) {
                Text("Settings")
                    .font(store.headingFont(size: 16))
                    .foregroundColor(primaryText)
                    .tracking(-0.2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)

            // Category Items
            VStack(spacing: 3) {
                ForEach(SettingsCategory.allCases) { category in
                    SidebarCategoryButton(
                        category: category,
                        isSelected: category == selectedCategory,
                        isDark: store.isDarkMode,
                        primaryText: primaryText,
                        headingFont: store.headingFont
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Footer version
            Text("Lean \(updater.marketingVersion) \(AppUpdater.releaseChannel)")
                .font(store.bodyFont(size: 10.5))
                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.25) : Color.black.opacity(0.30))
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Compact Category Bar
    private var compactCategoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(SettingsCategory.allCases) { category in
                    CompactCategoryButton(
                        category: category,
                        isSelected: category == selectedCategory,
                        isDark: store.isDarkMode,
                        primaryText: primaryText,
                        headingFont: store.headingFont
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Category Header
    private var categoryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedCategory.rawValue)
                .font(store.headingFont(size: 20))
                .foregroundColor(primaryText)
                .tracking(-0.3)

            Text(selectedCategory.subtitle)
                .font(store.bodyFont(size: 12))
                .foregroundColor(secondaryText)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Category Content Switcher
    @ViewBuilder
    private var contentForSelectedCategory: some View {
        switch selectedCategory {
        case .general:
            GeneralSection(store: store, updater: updater)
        case .topBar:
            TopBarCustomizerSection(store: store)
        case .appearance:
            AppearanceSection(store: store)
        case .tabs:
            TabsSection(store: store)
        case .browsing:
            BrowsingSection(store: store)
        case .privacy:
            PrivacySection(store: store)
        case .shortcuts:
            ShortcutsSection(store: store)
        case .history:
            HistorySection(store: store)
        case .downloads:
            DownloadsSection(store: store)
        case .importData:
            ImportDataSection(store: store)
        case .passwords:
            PasswordManagerSection(store: store)
        case .extensions:
            if #available(macOS 15.4, *) {
                ExtensionsSettingsSection(store: store)
            } else {
                Text("Extensions require macOS 15.4 or later.")
                    .font(store.leanUIFont.font(size: 12))
                    .foregroundColor(secondaryText)
            }
        }
    }
}

// MARK: - History Section
private struct HistorySection: View {
    @ObservedObject var store: LeanStore
    @State private var searchText = ""
    @State private var isClearingConfirm = false

    private var filteredItems: [HistoryItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.historyItems }
        let lower = trimmed.lowercased()
        return store.historyItems.filter { item in
            item.title.lowercased().contains(lower) ||
            item.url.absoluteString.lowercased().contains(lower) ||
            (item.url.host?.lowercased().contains(lower) == true)
        }
    }

    private struct HistoryGroup: Identifiable {
        let id: String
        let title: String
        let items: [HistoryItem]
    }

    private var groupedItems: [HistoryGroup] {
        let items = filteredItems
        guard !items.isEmpty else { return [] }

        var today: [HistoryItem] = []
        var yesterday: [HistoryItem] = []
        var thisWeek: [HistoryItem] = []
        var earlier: [HistoryItem] = []

        let calendar = Calendar.current
        let now = Date()

        for item in items {
            if calendar.isDateInToday(item.timestamp) {
                today.append(item)
            } else if calendar.isDateInYesterday(item.timestamp) {
                yesterday.append(item)
            } else if let diff = calendar.dateComponents([.day], from: item.timestamp, to: now).day, diff < 7 {
                thisWeek.append(item)
            } else {
                earlier.append(item)
            }
        }

        var groups: [HistoryGroup] = []
        if !today.isEmpty { groups.append(HistoryGroup(id: "today", title: "Today", items: today)) }
        if !yesterday.isEmpty { groups.append(HistoryGroup(id: "yesterday", title: "Yesterday", items: yesterday)) }
        if !thisWeek.isEmpty { groups.append(HistoryGroup(id: "thisWeek", title: "This Week", items: thisWeek)) }
        if !earlier.isEmpty { groups.append(HistoryGroup(id: "earlier", title: "Earlier", items: earlier)) }
        return groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Search and Filter Bar
            HStack(spacing: 8) {
                Ph.magnifyingGlass.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))

                TextField("Search history by title or domain...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(store.leanUIFont.font(size: 12.5))
                    .foregroundColor(store.isDarkMode ? Color.white : Color.black)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Ph.xCircle.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                store.isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 0.75)
            )

            // Header Stats & Clear Action
            HStack {
                let count = filteredItems.count
                Text(searchText.isEmpty ? "\(count) \(count == 1 ? "page" : "pages") recorded" : "\(count) \(count == 1 ? "result" : "results")")
                    .font(store.leanUIFont.font(size: 11, weight: .medium))
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                    .textCase(.uppercase)
                    .tracking(0.7)

                Spacer()

                if !store.historyItems.isEmpty {
                    if isClearingConfirm {
                        Button {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                                store.clearHistory()
                                isClearingConfirm = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Ph.trash.fill
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 10, height: 10)
                                Text("Confirm Clear All")
                                    .font(store.leanUIFont.font(size: 11, weight: .semibold))
                            }
                            .foregroundColor(Color.red.opacity(0.95))
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(
                                Color.red.opacity(store.isDarkMode ? 0.16 : 0.10),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                                isClearingConfirm = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                withAnimation {
                                    isClearingConfirm = false
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Ph.trash.fill
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 10, height: 10)
                                Text("Clear All")
                                    .font(store.leanUIFont.font(size: 11, weight: .medium))
                            }
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.60) : Color.black.opacity(0.55))
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // History List or Empty States
            if store.historyItems.isEmpty {
                // Empty History Canvas
                VStack(spacing: 12) {
                    Ph.clockCounterClockwise.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.30) : Color.black.opacity(0.30))

                    Text("No Browsing History")
                        .font(store.leanUIFont.font(size: 14, weight: .medium))
                        .foregroundColor(store.isDarkMode ? Color(white: 0.92) : Color(white: 0.15))

                    Text("Websites and pages you navigate to will be neatly organized here.")
                        .font(store.leanUIFont.font(size: 12))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 54)
            } else if filteredItems.isEmpty {
                // No Search Matches
                VStack(spacing: 12) {
                    Ph.magnifyingGlass.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.30) : Color.black.opacity(0.30))

                    Text("No Matches Found")
                        .font(store.leanUIFont.font(size: 14, weight: .medium))
                        .foregroundColor(store.isDarkMode ? Color(white: 0.92) : Color(white: 0.15))

                    Text("No visited pages matched \"\(searchText)\".")
                        .font(store.leanUIFont.font(size: 12))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.45))

                    Button {
                        searchText = ""
                    } label: {
                        Text("Clear Search")
                            .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.85) : Color.black.opacity(0.80))
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                // Chronological Grouped History List
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groupedItems) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(group.title) • \(group.items.count)")
                                .font(store.leanUIFont.font(size: 10.5, weight: .semibold))
                                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                                .textCase(.uppercase)
                                .tracking(0.8)
                                .padding(.horizontal, 2)

                            SettingsGroup(isDark: store.isDarkMode) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 {
                                        SettingsRowDivider(isDark: store.isDarkMode, inset: 44)
                                    }

                                    HistoryItemRow(item: item, store: store)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - History Item Row
private struct HistoryItemRow: View {
    let item: HistoryItem
    @ObservedObject var store: LeanStore

    @State private var isHovered = false
    @State private var isCopied = false

    private var formattedTime: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(item.timestamp) {
            formatter.dateFormat = "h:mm a"
        } else if Calendar.current.isDateInYesterday(item.timestamp) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: item.timestamp)
    }

    private var displayHostAndPath: String {
        let host = item.url.host ?? ""
        let path = item.url.path.isEmpty || item.url.path == "/" ? "" : item.url.path
        return "\(host)\(path)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Favicon
            SiteFaviconView(url: item.url, isDark: store.isDarkMode, size: 18)
                .frame(width: 22, height: 22)

            // Titles & URL
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(store.leanUIFont.font(size: 13, weight: .medium))
                    .foregroundColor(store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12))
                    .lineLimit(1)

                Text(displayHostAndPath)
                    .font(store.leanUIFont.font(size: 11))
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            // Timestamp or Hover Actions
            HStack(spacing: 6) {
                if isHovered {
                    // Copy URL Button
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            isCopied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                isCopied = false
                            }
                        }
                    } label: {
                        (isCopied ? Ph.check.bold : Ph.copy.fill)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                            .foregroundColor(isCopied ? Color.green : (store.isDarkMode ? Color.white.opacity(0.7) : Color.black.opacity(0.65)))
                            .frame(width: 26, height: 26)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(isCopied ? "Copied" : "Copy Link")

                    // Open in New Tab Button
                    Button {
                        store.openHistoryItem(item, inNewTab: true)
                    } label: {
                        Ph.arrowSquareOut.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.7) : Color.black.opacity(0.65))
                            .frame(width: 26, height: 26)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Open in New Tab")

                    // Delete Entry Button
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            store.deleteHistoryItem(id: item.id)
                        }
                    } label: {
                        Ph.trash.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.6) : Color.black.opacity(0.55))
                            .frame(width: 26, height: 26)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Remove from History")
                } else {
                    Text(formattedTime)
                        .font(store.leanUIFont.font(size: 11))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
                        .padding(.trailing, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(
            isHovered
                ? (store.isDarkMode ? Color.white.opacity(0.035) : Color.black.opacity(0.02))
                : Color.clear
        )
        .onHover { isHovered = $0 }
        .onTapGesture {
            let inNewTab = NSEvent.modifierFlags.contains(.command)
            store.openHistoryItem(item, inNewTab: inNewTab)
        }
    }
}


// MARK: - 1. General Section (Zen Mode & Window Frame)
private struct GeneralSection: View {
    @ObservedObject var store: LeanStore
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(isDark: store.isDarkMode) {
                CustomToggleRow(
                    title: "Zen mode",
                    subtitle: "Distraction-free browsing. The top navigation bar hides completely and reveals smoothly when you hover the top edge.",
                    isOn: $store.enableZenMode,
                    isDark: store.isDarkMode,
                    uiFont: store.leanUIFont
                )

                if store.tabLayout != .sidebar {
                    SettingsRowDivider(isDark: store.isDarkMode)

                    CustomToggleRow(
                        title: "Window frame",
                        subtitle: "Encase the web view in an elegant, minimal outer border with adaptive light/dark appearance.",
                        isOn: $store.enableWindowBorder,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont
                    )
                }

                if store.enableWindowBorder {
                    SettingsRowDivider(isDark: store.isDarkMode)

                    FrameWidthPickerRow(
                        store: store,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont
                    )
                }
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: store.enableZenMode)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: store.enableWindowBorder)

            SettingsGroup(isDark: store.isDarkMode) {
                CustomToggleRow(
                    title: "Automatically check for updates",
                    subtitle: "Lean checks its GitHub release feed in the background. Updates are signed, so they stay safe without notarization.",
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ),
                    isDark: store.isDarkMode,
                    uiFont: store.leanUIFont
                )

                SettingsRowDivider(isDark: store.isDarkMode)

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        Text("Lean \(updater.marketingVersion) \(AppUpdater.releaseChannel)")
                            .font(store.leanUIFont.font(size: 13, weight: .medium))
                            .foregroundColor(store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12))
                        Text("Build \(updater.buildVersion) · Signed updates from GitHub releases.")
                            .font(store.leanUIFont.font(size: 11.5))
                            .foregroundColor(store.isDarkMode ? Color(white: 0.50) : Color(white: 0.48))
                    }

                    Spacer(minLength: 16)

                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Text("Check Now")
                            .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.75) : Color.black.opacity(0.65))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!updater.canCheckForUpdates)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            SettingsGroup(isDark: store.isDarkMode) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Onboarding tour")
                            .font(store.leanUIFont.font(size: 13, weight: .medium))
                            .foregroundColor(store.isDarkMode ? .white : .black)

                        Text("Replay the interactive story and onboarding walkthrough.")
                            .font(store.leanUIFont.font(size: 11.5))
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                    }

                    Spacer()

                    Button {
                        store.startOnboarding()
                    } label: {
                        Text("Start Tour")
                            .font(store.leanUIFont.font(size: 12, weight: .medium))
                            .foregroundColor(store.isDarkMode ? .white : .black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - 2. Top Bar Customizer Section
private struct TopBarCustomizerSection: View {
    @ObservedObject var store: LeanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Reset Button & Guidance
            HStack {
                Text("Drag icons between shelves or click any icon to toggle its visibility.")
                    .font(store.leanUIFont.font(size: 12))
                    .foregroundColor(store.isDarkMode ? Color(white: 0.50) : Color(white: 0.48))

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.resetToolbarItems()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Ph.arrowCounterClockwise.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10, height: 10)
                        Text("Reset Default")
                            .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.75) : Color.black.opacity(0.65))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }

            // Zone 1: Active in Top Bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shown in Top Bar")
                        .font(store.leanUIFont.font(size: 11, weight: .semibold))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Spacer()

                    Text("\(store.shownToolbarItems.count) active")
                        .font(store.leanUIFont.font(size: 11, weight: .medium))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.40))
                }

                ToolbarShelf(
                    items: store.shownToolbarItems,
                    isShownShelf: true,
                    store: store,
                    onDrop: { rawId in
                        store.moveToolbarItem(withId: rawId, toShown: true)
                    },
                    onToggle: { item in
                        store.hideToolbarItem(item)
                    }
                )
            }

            // Zone 2: Hidden / Available
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Available to Add")
                        .font(store.leanUIFont.font(size: 11, weight: .semibold))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Spacer()

                    Text("\(store.hiddenToolbarItems.count) hidden")
                        .font(store.leanUIFont.font(size: 11, weight: .medium))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.40))
                }

                ToolbarShelf(
                    items: store.hiddenToolbarItems,
                    isShownShelf: false,
                    store: store,
                    onDrop: { rawId in
                        store.moveToolbarItem(withId: rawId, toShown: false)
                    },
                    onToggle: { item in
                        store.showToolbarItem(item)
                    }
                )
            }
        }
    }
}

// MARK: - Toolbar Shelf Container (Tactile Drop Target)
private struct ToolbarShelf: View {
    let items: [ToolbarItemType]
    let isShownShelf: Bool
    @ObservedObject var store: LeanStore
    let onDrop: (String) -> Void
    let onToggle: (ToolbarItemType) -> Void

    @State private var isTargeted = false

    private var shelfBackground: Color {
        if isShownShelf {
            return store.isDarkMode ? Color.white.opacity(0.03) : Color.black.opacity(0.02)
        } else {
            return store.isDarkMode ? Color.white.opacity(0.015) : Color.black.opacity(0.01)
        }
    }

    private var shelfBorderColor: Color {
        if isTargeted {
            return store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.35)
        } else {
            return store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(shelfBackground)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(shelfBorderColor, lineWidth: isTargeted ? 1.5 : 0.75)

            if items.isEmpty {
                HStack(spacing: 8) {
                    (isShownShelf ? Ph.tray.fill : Ph.checkCircle.fill)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.3) : Color.black.opacity(0.3))

                    Text(isShownShelf ? "No icons visible in top bar" : "All available icons are currently shown")
                        .font(store.leanUIFont.font(size: 12))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        ToolbarInteractiveChip(
                            item: item,
                            isShown: isShownShelf,
                            store: store,
                            onToggle: { onToggle(item) }
                        )
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(height: 64)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: items)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [UTType.text.identifier, UTType.plainText.identifier], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    if let string = object as? String {
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                onDrop(string)
                            }
                        }
                    }
                }
                return true
            }
            return false
        }
    }
}

// MARK: - Toolbar Interactive Chip
private struct ToolbarInteractiveChip: View {
    let item: ToolbarItemType
    let isShown: Bool
    @ObservedObject var store: LeanStore
    let onToggle: () -> Void

    @State private var isHovered = false

    private var iconColor: Color {
        if isHovered {
            return store.isDarkMode ? Color.white : Color.black
        }
        return store.isDarkMode ? Color.white.opacity(0.80) : Color.black.opacity(0.70)
    }

    private var chipBgColor: Color {
        if isHovered {
            return store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        }
        return store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var chipBorderColor: Color {
        if isHovered {
            return store.isDarkMode ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
        }
        return store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    private var labelColor: Color {
        if isHovered {
            return store.isDarkMode ? Color.white.opacity(0.85) : Color.black.opacity(0.85)
        }
        return store.isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.45)
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                onToggle()
            }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    item.icon.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundColor(iconColor)
                        .frame(width: 36, height: 30)
                        .background(
                            chipBgColor,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(chipBorderColor, lineWidth: 0.5)
                        )

                    if isHovered {
                        (isShown ? Ph.minusCircle.fill : Ph.plusCircle.fill)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 9, height: 9)
                            .foregroundColor(isShown ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
                            .offset(x: 3, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(item.displayName)
                    .font(store.leanUIFont.font(size: 10, weight: .medium))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(isShown ? "Hide" : "Show") \(item.displayName) (click or drag)")
        .onDrag {
            NSItemProvider(object: item.rawValue as NSString)
        }
    }
}

// MARK: - 3. Appearance Section
private struct AppearanceSection: View {
    @ObservedObject var store: LeanStore
    @EnvironmentObject private var dropdownState: DropdownMenuState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Theme Selector
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Interface Theme", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                CustomSegmentedPicker(
                    options: [
                        SegmentOption(id: AppTheme.light.rawValue, label: "Light", icon: .sun),
                        SegmentOption(id: AppTheme.dark.rawValue, label: "Dark", icon: .moon),
                        SegmentOption(id: AppTheme.system.rawValue, label: "System", icon: .circleHalf)
                    ],
                    selectedId: store.theme.rawValue,
                    isDark: store.isDarkMode,
                    uiFont: store.leanUIFont
                ) { newId in
                    if let theme = AppTheme(rawValue: newId) {
                        store.theme = theme
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel(
                    "Browser UI",
                    uiFont: store.leanUIFont,
                    isDark: store.isDarkMode,
                    headingWeight: store.uiHeadingWeight,
                    bodyWeight: store.uiBodyWeight
                )

                SettingsGroup(isDark: store.isDarkMode) {
                    SettingsSliderRow(
                        title: "Interface size",
                        subtitle: "Scales browser controls, icons, tabs, sidebars, and browser text",
                        uiFont: store.leanUIFont,
                        isDark: store.isDarkMode,
                        headingWeight: store.uiHeadingWeight,
                        bodyWeight: store.uiBodyWeight
                    ) {
                        SettingsValueSlider(
                            value: $store.browserUIScalePercent,
                            range: 80...120,
                            step: 5,
                            label: "UI",
                            valueSuffix: "%",
                            isDark: store.isDarkMode,
                            uiFont: store.leanUIFont
                        )
                    }
                }
            }

            // Typography
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel(
                    "Typography",
                    uiFont: store.leanUIFont,
                    isDark: store.isDarkMode,
                    headingWeight: store.uiHeadingWeight,
                    bodyWeight: store.uiBodyWeight
                )

                SettingsGroup(isDark: store.isDarkMode) {
                    FontPickerRow(
                        title: "Lean UI",
                        subtitle: "Typeface applied to tabs, omnibar, and browser controls",
                        selection: $store.leanUIFont,
                        uiFont: store.leanUIFont,
                        isDark: store.isDarkMode,
                        pickerId: "fontPicker_leanUI",
                        headingWeight: store.uiHeadingWeight,
                        bodyWeight: store.uiBodyWeight
                    )

                    SettingsRowDivider(isDark: store.isDarkMode)

                    FontWeightSliderRow(
                        title: "Heading weight",
                        subtitle: "\(store.uiHeadingWeight.name) (\(store.uiHeadingWeight.rawValue)) · Thickness of titles, tabs, and headers",
                        value: $store.uiHeadingWeight,
                        label: "H",
                        uiFont: store.leanUIFont,
                        isDark: store.isDarkMode,
                        headingWeight: store.uiHeadingWeight,
                        bodyWeight: store.uiBodyWeight
                    )

                    SettingsRowDivider(isDark: store.isDarkMode)

                    FontWeightSliderRow(
                        title: "Body text weight",
                        subtitle: "\(store.uiBodyWeight.name) (\(store.uiBodyWeight.rawValue)) · Thickness of omnibar, subtitles, and descriptions",
                        value: $store.uiBodyWeight,
                        label: "B",
                        uiFont: store.leanUIFont,
                        isDark: store.isDarkMode,
                        headingWeight: store.uiHeadingWeight,
                        bodyWeight: store.uiBodyWeight
                    )

                    SettingsRowDivider(isDark: store.isDarkMode)

                    FontPickerRow(
                        title: "Web pages",
                        subtitle: "Typeface override for readable webpage text and browser tab titles",
                        selection: $store.webPageFont,
                        uiFont: store.leanUIFont,
                        isDark: store.isDarkMode,
                        pickerId: "fontPicker_webPages",
                        headingWeight: store.uiHeadingWeight,
                        bodyWeight: store.uiBodyWeight
                    )
                }
                .zIndex(dropdownState.activeId?.starts(with: "fontPicker_") == true ? 100 : 1)

                // Typography Live Preview Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Typography Preview")
                            .font(store.headingFont(size: 13.5))
                            .foregroundColor(store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12))

                        Spacer()

                        Text("\(store.leanUIFont.rawValue) · H:\(store.uiHeadingWeight.rawValue) B:\(store.uiBodyWeight.rawValue)")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                    }

                    Text("The quick brown fox jumps over the lazy dog — browser controls, tabs, and navigation text reflect these font weights in real time.")
                        .font(store.bodyFont(size: 12))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.60) : Color.black.opacity(0.55))
                        .lineSpacing(2)
                }
                .padding(14)
                .background(
                    store.isDarkMode ? Color.white.opacity(0.025) : Color.black.opacity(0.015),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(store.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.04), lineWidth: 0.75)
                )
            }
            .zIndex(dropdownState.activeId?.starts(with: "fontPicker_") == true ? 100 : 1)
        }
    }
}

// MARK: - 4. Tabs Section
private struct TabsSection: View {
    @ObservedObject var store: LeanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Tab Layout Setting (Top of Window vs Sidebar)
            VStack(alignment: .leading, spacing: 10) {
                SettingsHeaderLabel("Tab Layout", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                TabLayoutPickerView(store: store)
            }

            // Tab Display Mode
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Tab Display Style", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                CustomSegmentedPicker(
                    options: [
                        SegmentOption(id: TabDisplayMode.textOnly.rawValue, label: "Text Only", icon: .textAlignLeft),
                        SegmentOption(id: TabDisplayMode.iconOnly.rawValue, label: "Icon Only", icon: .squaresFour),
                        SegmentOption(id: TabDisplayMode.hybrid.rawValue, label: "Hybrid", icon: .checkSquare)
                    ],
                    selectedId: store.tabDisplayMode.rawValue,
                    isDark: store.isDarkMode,
                    uiFont: store.leanUIFont
                ) { newId in
                    if let mode = TabDisplayMode(rawValue: newId) {
                        store.tabDisplayMode = mode
                    }
                }
            }

            // Tab Behaviors
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Behaviors", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                SettingsGroup(isDark: store.isDarkMode) {
                    CustomToggleRow(
                        title: "Expand active tab title",
                        subtitle: "Shows the full page title on the active tab while condensing inactive tabs.",
                        isOn: $store.showFullTitleOnActiveTab,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont
                    )

                    SettingsRowDivider(isDark: store.isDarkMode)

                    CustomToggleRow(
                        title: "Tab switcher previews",
                        subtitle: "Render visual webpage snapshot thumbnails during ⌃Tab switching.",
                        isOn: $store.enableThumbnailsInTabSwitcher,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Sleeping tabs", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                SettingsGroup(isDark: store.isDarkMode) {
                    CustomToggleRow(
                        title: "Automatically sleep inactive tabs",
                        subtitle: "Release their WebKit views after they have been inactive.",
                        isOn: $store.autoSleepTabsEnabled,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont
                    )
                    if store.autoSleepTabsEnabled {
                        SettingsRowDivider(isDark: store.isDarkMode)
                        HStack {
                            Text("Sleep after")
                                .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                            Spacer()
                            Picker("Sleep after", selection: $store.autoSleepAfterMinutes) {
                                Text("5 minutes").tag(5)
                                Text("15 minutes").tag(15)
                                Text("30 minutes").tag(30)
                                Text("60 minutes").tag(60)
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
                Text("Tabs with active playback, camera or microphone use, downloads, loading, unsaved form input, or cross-origin/sandboxed frames stay awake. Sleeping tabs restore the URL and scroll position.")
                    .font(store.leanUIFont.font(size: 11.5))
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
            }
        }
    }
}

// MARK: - Tab Layout Picker Component
private struct TabLayoutPickerView: View {
    @ObservedObject var store: LeanStore

    var body: some View {
        HStack(spacing: 20) {
            TabLayoutCard(
                layout: .top,
                isSelected: store.tabLayout == .top,
                isDark: store.isDarkMode,
                uiFont: store.leanUIFont
            ) {
                store.tabLayout = .top
            }

            TabLayoutCard(
                layout: .sidebar,
                isSelected: store.tabLayout == .sidebar,
                isDark: store.isDarkMode,
                uiFont: store.leanUIFont
            ) {
                store.tabLayout = .sidebar
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TabLayoutCard: View {
    let layout: TabLayout
    let isSelected: Bool
    let isDark: Bool
    let uiFont: LeanFont
    let onSelect: () -> Void

    @State private var isHovered = false

    private var windowFrameBackground: Color {
        isDark ? Color(red: 40/255, green: 40/255, blue: 44/255) : Color(white: 0.93)
    }

    private var contentAreaBackground: Color {
        isDark ? Color(red: 26/255, green: 26/255, blue: 28/255) : Color(white: 0.84)
    }

    private var tabShapeColor: Color {
        isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.22)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 9) {
                // Miniature window illustration
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(windowFrameBackground)

                    if layout == .top {
                        topWindowIllustration
                    } else {
                        sidebarWindowIllustration
                    }
                }
                .frame(width: 148, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected
                                ? (isDark ? Color.white : Color.black)
                                : (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .shadow(
                    color: isSelected
                        ? (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.14))
                        : (isHovered ? Color.black.opacity(0.08) : Color.clear),
                    radius: isSelected ? 6 : 4,
                    x: 0,
                    y: 2
                )

                // Label below card
                Text(layout.title)
                    .font(uiFont.font(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(
                        isSelected
                            ? (isDark ? Color.white : Color.black)
                            : (isDark ? Color.white.opacity(0.60) : Color.black.opacity(0.55))
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    // Window with horizontal tabs on top
    private var topWindowIllustration: some View {
        VStack(spacing: 5) {
            // Top bar
            HStack(spacing: 4) {
                // Traffic light dots
                HStack(spacing: 3) {
                    Circle().fill(Color(red: 255/255, green: 95/255, blue: 86/255)).frame(width: 4.5, height: 4.5)
                    Circle().fill(Color(red: 255/255, green: 189/255, blue: 46/255)).frame(width: 4.5, height: 4.5)
                    Circle().fill(Color(red: 39/255, green: 201/255, blue: 63/255)).frame(width: 4.5, height: 4.5)
                }

                Spacer(minLength: 2)

                // 3 horizontal tabs
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tabShapeColor)
                        .frame(width: 26, height: 8.5)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tabShapeColor)
                        .frame(width: 26, height: 8.5)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tabShapeColor)
                        .frame(width: 26, height: 8.5)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 14)

            // Inner viewport content area
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(contentAreaBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .padding(.top, 4)
    }

    // Window with vertical tabs in sidebar
    private var sidebarWindowIllustration: some View {
        HStack(spacing: 5) {
            // Sidebar area
            VStack(alignment: .leading, spacing: 5) {
                // Traffic light dots
                HStack(spacing: 3) {
                    Circle().fill(Color(red: 255/255, green: 95/255, blue: 86/255)).frame(width: 4.5, height: 4.5)
                    Circle().fill(Color(red: 255/255, green: 189/255, blue: 46/255)).frame(width: 4.5, height: 4.5)
                    Circle().fill(Color(red: 39/255, green: 201/255, blue: 63/255)).frame(width: 4.5, height: 4.5)
                }
                .padding(.top, 5)

                // 3 vertical tab pills
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tabShapeColor)
                        .frame(width: 32, height: 8)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tabShapeColor)
                        .frame(width: 32, height: 8)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tabShapeColor)
                        .frame(width: 32, height: 8)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .frame(width: 42)

            // Inner viewport content area
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(contentAreaBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 4)
                .padding(.trailing, 4)
        }
    }
}

// MARK: - 5. Browsing Section
private struct BrowsingSection: View {
    @ObservedObject var store: LeanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Scrollbar Style
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Scrollbar Appearance", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                CustomSegmentedPicker(
                    options: [
                        SegmentOption(id: ScrollbarStyle.hidden.rawValue, label: "Hidden", icon: .eyeSlash),
                        SegmentOption(id: ScrollbarStyle.thin.rawValue, label: "Thin", icon: .list),
                        SegmentOption(id: ScrollbarStyle.normal.rawValue, label: "Default", icon: .sliders)
                    ],
                    selectedId: store.scrollbarStyle.rawValue,
                    isDark: store.isDarkMode,
                    uiFont: store.leanUIFont
                ) { newId in
                    if let style = ScrollbarStyle(rawValue: newId) {
                        store.scrollbarStyle = style
                    }
                }
            }

            // Scrolling Mechanics
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Scrolling Mechanics", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                SettingsGroup(isDark: store.isDarkMode) {
                    CustomToggleRow(
                        title: "Smooth scrolling",
                        subtitle: "Fluid momentum physics for trackpad gestures and page navigation.",
                        isOn: $store.smoothScrollingEnabled,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont
                    )
                }
            }
        }
    }
}

// MARK: - 6. Privacy & Data Section
private struct PrivacySection: View {
    @ObservedObject var store: LeanStore
    @EnvironmentObject private var dropdownState: DropdownMenuState
    @State private var isUpdatingFilters = false
    @State private var filterStatus: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Search & Protection
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Search & Protection", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                SettingsGroup(isDark: store.isDarkMode) {
                    SearchEnginePickerRow(
                        selection: $store.searchEngine,
                        uiFont: store.leanUIFont,
                        isDark: store.isDarkMode
                    )

                    SettingsRowDivider(isDark: store.isDarkMode)

                    CustomToggleRow(
                        title: "Tracker & ad filtering",
                        subtitle: "Built-in network and cosmetic blocking powered by EasyList, EasyPrivacy, and uBlock filters.",
                        isOn: $store.adBlockingEnabled,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont
                    )

                    if let host = store.selectedTab?.url?.host {
                        SettingsRowDivider(isDark: store.isDarkMode)
                        CustomToggleRow(
                            title: "Block on this site",
                            subtitle: "Only \(host)",
                            isOn: Binding(
                                get: { store.isAdBlockingEnabled(for: host) },
                                set: { store.setAdBlocking($0, for: host) }
                            ),
                            isDark: store.isDarkMode,
                            uiFont: store.leanUIFont
                        )
                        .disabled(!store.adBlockingEnabled)
                    }

                    SettingsRowDivider(isDark: store.isDarkMode)

                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2.5) {
                            Text("Filter lists")
                                .font(store.leanUIFont.font(size: 13, weight: .medium))
                                .foregroundColor(primaryText)
                            Text(filterListsSubtitle)
                                .font(store.leanUIFont.font(size: 11.5))
                                .foregroundColor(secondaryText)
                        }

                        Spacer(minLength: 16)

                        if isUpdatingFilters {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                Task { await updateFilterLists() }
                            } label: {
                                Text("Update now")
                                    .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                                    .foregroundColor(primaryText)
                                    .padding(.horizontal, 12)
                                    .frame(height: 28)
                                    .background(
                                        store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(isUpdatingFilters)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .zIndex(dropdownState.activeId == "searchEnginePicker" ? 100 : 1)
            }
            .zIndex(dropdownState.activeId == "searchEnginePicker" ? 100 : 1)

            if !store.adBlockingExcludedHosts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsHeaderLabel("Sites with blocking paused", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                    SettingsGroup(isDark: store.isDarkMode) {
                        ForEach(store.adBlockingExcludedHosts.sorted(), id: \.self) { host in
                            HStack {
                                Text(host)
                                    .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                                    .foregroundColor(primaryText)
                                Spacer()
                                SettingsActionButton("Turn on", isDark: store.isDarkMode) {
                                    store.setAdBlocking(true, for: host)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Camera and microphone", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                MediaPermissionSection(permissions: store.mediaPermissionStore, store: store)
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Data Management", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                SettingsGroup(isDark: store.isDarkMode) {
                    DataClearRow(
                        title: "History",
                        subtitle: "Clear Lean's recorded browsing history.",
                        confirmation: "Clear browsing history?",
                        store: store
                    ) { done in
                        store.clearHistory()
                        done()
                    }
                    SettingsRowDivider(isDark: store.isDarkMode)
                    DataClearRow(
                        title: "Cookies and site data",
                        subtitle: "Signs you out and clears stored website data.",
                        confirmation: "Clear cookies and all website storage?",
                        store: store,
                        clear: store.clearCookiesAndSiteData
                    )
                    SettingsRowDivider(isDark: store.isDarkMode)
                    DataClearRow(
                        title: "Cache",
                        subtitle: "Clear cached files and images. This does not sign you out.",
                        confirmation: "Clear WebKit cache?",
                        store: store,
                        clear: store.clearWebCache
                    )
                }
            }
        }
    }

    private var filterListsSubtitle: String {
        if let filterStatus {
            return filterStatus
        }
        let count = ContentBlocker.cachedRuleCount
        if let updated = ContentBlocker.lastUpdatedDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let ago = formatter.localizedString(for: updated, relativeTo: Date())
            if count > 0 {
                return "\(count.formatted()) rules · updated \(ago)"
            }
            return "Updated \(ago)"
        }
        if count > 0 {
            return "\(count.formatted()) rules · never updated on this Mac"
        }
        return "Lists download automatically and refresh weekly"
    }

    private func updateFilterLists() async {
        isUpdatingFilters = true
        defer { isUpdatingFilters = false }
        if let result = await ContentBlocker.refreshNow() {
            filterStatus = "\(result.ruleCount.formatted()) rules · just updated"
        } else {
            filterStatus = "Update failed — kept existing lists"
        }
    }

    private var primaryText: Color {
        store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12)
    }

    private var secondaryText: Color {
        store.isDarkMode ? Color(white: 0.50) : Color(white: 0.48)
    }
}

private struct MediaPermissionSection: View {
    @ObservedObject var permissions: MediaPermissionStore
    @ObservedObject var store: LeanStore

    private var grouped: [(origin: String, decisions: [MediaPermissionStore.Decision])] {
        Dictionary(grouping: permissions.savedDecisions, by: \.origin)
            .map { (origin: $0.key, decisions: $0.value) }
            .sorted { $0.origin < $1.origin }
    }

    var body: some View {
        SettingsGroup(isDark: store.isDarkMode) {
            if grouped.isEmpty {
                Text("No saved camera or microphone choices.")
                    .font(store.leanUIFont.font(size: 11.5))
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ForEach(grouped, id: \.origin) { site in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(site.origin)
                                .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                            Spacer()
                            SettingsActionButton("Forget choices", isDark: store.isDarkMode, destructive: true) {
                                permissions.clear(origin: site.origin)
                            }
                        }
                        ForEach(site.decisions) { decision in
                            Text("\(decision.label): \(decision.allowed ? "Allowed" : "Denied")")
                                .font(store.leanUIFont.font(size: 11.5))
                                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                        }
                    }
                    .padding(14)
                    if site.origin != grouped.last?.origin { SettingsRowDivider(isDark: store.isDarkMode) }
                }
                SettingsRowDivider(isDark: store.isDarkMode)
                HStack {
                    Spacer()
                    SettingsActionButton("Forget all choices", isDark: store.isDarkMode, destructive: true) {
                        permissions.clear()
                    }
                }
                .padding(10)
            }
        }
    }
}

private struct DataClearRow: View {
    let title: String
    let subtitle: String
    let confirmation: String
    @ObservedObject var store: LeanStore
    let clear: (@escaping @Sendable () -> Void) -> Void

    @State private var isConfirming = false
    @State private var cleared = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(store.leanUIFont.font(size: 13, weight: .medium))
                    .foregroundColor(store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12))
                Text(isConfirming ? confirmation : subtitle)
                    .font(store.leanUIFont.font(size: 11.5))
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
            }
            Spacer(minLength: 12)
            if isConfirming {
                SettingsActionButton("Cancel", isDark: store.isDarkMode) { isConfirming = false }
                SettingsActionButton("Confirm", isDark: store.isDarkMode, destructive: true) {
                    isConfirming = false
                    clear {
                        DispatchQueue.main.async {
                            cleared = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { cleared = false }
                        }
                    }
                }
            } else {
                SettingsActionButton(cleared ? "Cleared" : "Clear", isDark: store.isDarkMode) {
                    isConfirming = true
                }
                .disabled(cleared)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Keymaps / Shortcuts Section
private struct ShortcutsSection: View {
    @ObservedObject var store: LeanStore
    @State private var searchQuery = ""
    @State private var selectedGroup: ShortcutAction.Group = .all
    @State private var triggeredActionId: String? = nil
    @State private var recordingAction: ShortcutAction? = nil
    @State private var recordMonitor: Any? = nil

    private var filteredActions: [ShortcutAction] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ShortcutAction.allCases.filter { action in
            let matchesGroup = selectedGroup == .all || action.group == selectedGroup
            guard matchesGroup else { return false }
            if trimmed.isEmpty { return true }
            let combo = store.shortcut(for: action)
            let matchesTitle = action.title.lowercased().contains(trimmed)
            let matchesDesc = action.description.lowercased().contains(trimmed)
            let matchesKey = combo.displayKeys.joined(separator: " ").lowercased().contains(trimmed)
            return matchesTitle || matchesDesc || matchesKey
        }
    }

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let recording = recordingAction else { return event }

            // Check for cancel with plain Escape
            if event.keyCode == 53 && event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty {
                stopRecording()
                return nil
            }

            if let combo = CustomKeyCombo.from(event: event) {
                store.setShortcut(combo, for: recording)
                stopRecording()
                return nil
            }

            return nil
        }
    }

    private func stopRecording() {
        if let monitor = recordMonitor {
            NSEvent.removeMonitor(monitor)
            recordMonitor = nil
        }
        withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
            recordingAction = nil
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Search & Filter Header
            VStack(spacing: 12) {
                // Search Input Field
                HStack(spacing: 8) {
                    Ph.magnifyingGlass.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.35))

                    TextField("Search shortcuts or keys...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(store.leanUIFont.font(size: 12.5))
                        .foregroundColor(primaryText)

                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Ph.xCircle.fill
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                                .foregroundColor(secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
                )

                // Category Filter Pills & Reset All
                HStack(spacing: 5) {
                    ForEach(ShortcutAction.Group.allCases) { group in
                        let isSelected = group == selectedGroup
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                                selectedGroup = group
                            }
                        } label: {
                            Text(group.rawValue)
                                .font(store.leanUIFont.font(size: 11, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(
                                    isSelected
                                        ? primaryText
                                        : (store.isDarkMode ? Color.white.opacity(0.50) : Color.black.opacity(0.45))
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    isSelected
                                        ? (store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                        : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if !store.customShortcuts.isEmpty {
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                store.resetAllShortcuts()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Ph.arrowCounterClockwise.fill
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 10, height: 10)
                                Text("Reset All")
                                    .font(store.leanUIFont.font(size: 11, weight: .medium))
                            }
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.6) : Color.black.opacity(0.55))
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Restore all shortcuts to factory defaults")
                    }
                }
            }

            // Keymaps Card
            SettingsGroup(isDark: store.isDarkMode) {
                VStack(spacing: 0) {
                    ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, action in
                        let combo = store.shortcut(for: action)
                        let isRecording = recordingAction == action
                        let isCustom = store.isCustomized(action)
                        let wasTriggered = triggeredActionId == action.rawValue

                        HStack(spacing: 12) {
                            // Action Title & Description
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(action.title)
                                        .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                                        .foregroundColor(primaryText)

                                    if isCustom {
                                        Text("Modified")
                                            .font(store.leanUIFont.font(size: 9.5, weight: .medium))
                                            .foregroundColor(Color(red: 52/255, green: 199/255, blue: 89/255))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(
                                                Color(red: 52/255, green: 199/255, blue: 89/255).opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                            )
                                    }
                                }

                                Text(action.description)
                                    .font(store.leanUIFont.font(size: 11))
                                    .foregroundColor(secondaryText)
                            }

                            Spacer(minLength: 16)

                            // Interactive Test Trigger Indicator
                            Button {
                                action.performAction(in: store)
                                withAnimation(.spring(response: 0.18, dampingFraction: 0.75)) {
                                    triggeredActionId = action.rawValue
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    if triggeredActionId == action.rawValue {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            triggeredActionId = nil
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if wasTriggered {
                                        Ph.check.bold
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 9.5, height: 9.5)
                                            .foregroundColor(Color(red: 48/255, green: 209/255, blue: 88/255))
                                    }
                                    Text(wasTriggered ? "Triggered" : "Test")
                                        .font(store.leanUIFont.font(size: 10, weight: .medium))
                                        .foregroundColor(
                                            wasTriggered
                                                ? Color(red: 48/255, green: 209/255, blue: 88/255)
                                                : (store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.35))
                                        )
                                }
                                .padding(.horizontal, 7)
                                .frame(height: 22)
                                .background(
                                    wasTriggered
                                        ? Color(red: 48/255, green: 209/255, blue: 88/255).opacity(0.12)
                                        : (store.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.04)),
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Click to test-trigger this action")

                            // Keycap Badges / Shortcut Recorder
                            Button {
                                if isRecording {
                                    stopRecording()
                                } else {
                                    startRecording(action)
                                }
                            } label: {
                                if isRecording {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(Color(red: 52/255, green: 199/255, blue: 89/255))
                                            .frame(width: 5, height: 5)
                                        Text("Press keys... (Esc to cancel)")
                                            .font(store.leanUIFont.font(size: 10.5, weight: .medium))
                                            .foregroundColor(store.adaptiveTheme.primaryText)
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(height: 23)
                                    .background(
                                        Color(red: 52/255, green: 199/255, blue: 89/255).opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(Color(red: 52/255, green: 199/255, blue: 89/255).opacity(0.45), lineWidth: 1)
                                    )
                                } else {
                                    HStack(spacing: 3) {
                                        ForEach(Array(combo.displayKeys.enumerated()), id: \.offset) { _, key in
                                             KeycapBadge(key: key, isDark: store.isDarkMode, font: store.leanUIFont)
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        store.isDarkMode ? Color.white.opacity(0.03) : Color.black.opacity(0.02),
                                        in: RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                            .stroke(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 0.5)
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .help(isRecording ? "Press new key combination or Escape to cancel" : "Click to customize this keyboard shortcut")

                            // Reset single shortcut button if modified
                            if isCustom {
                                Button {
                                    withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                                        store.resetShortcut(for: action)
                                    }
                                } label: {
                                    Ph.arrowCounterClockwise.fill
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 9.5, height: 9.5)
                                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.40))
                                        .frame(width: 20, height: 20)
                                        .background(
                                            store.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.04),
                                            in: Circle()
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Reset this shortcut to default")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if index < filteredActions.count - 1 {
                            Divider()
                                .background(dividerColor)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var primaryText: Color {
        store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12)
    }

    private var secondaryText: Color {
        store.isDarkMode ? Color(white: 0.50) : Color(white: 0.48)
    }

    private var dividerColor: Color {
        store.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
    }
}

// MARK: - Keycap Badge
private struct KeycapBadge: View {
    let key: String
    let isDark: Bool
    let font: LeanFont

    private var keyFont: Font {
        let size: CGFloat = key.count > 1 ? 10.5 : 12.0
        return font.font(size: size, weight: .medium)
    }

    private var textColor: Color {
        isDark ? Color(white: 0.88) : Color(white: 0.16)
    }

    private var badgeBackground: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }

    private var badgeBorder: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }

    private var shadowColor: Color {
        isDark ? Color.black.opacity(0.25) : Color.black.opacity(0.04)
    }

    private var hPadding: CGFloat {
        key.count > 1 ? 6 : 5
    }

    var body: some View {
        Text(key)
            .font(keyFont)
            .foregroundColor(textColor)
            .padding(.horizontal, hPadding)
            .frame(minWidth: 20)
            .frame(height: 21)
            .background(badgeBackground, in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .stroke(badgeBorder, lineWidth: 0.5)
            )
            .shadow(color: shadowColor, radius: 1, x: 0, y: 1)
    }
}

// MARK: - Downloads Section
private struct DownloadsSection: View {
    @ObservedObject var store: LeanStore
    @State private var searchText = ""

    private var filteredItems: [DownloadItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.downloadManager.downloads }
        let lower = trimmed.lowercased()
        return store.downloadManager.downloads.filter {
            $0.fileName.lowercased().contains(lower)
                || $0.destinationURL.path.lowercased().contains(lower)
        }
    }

    private var primaryText: Color {
        store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12)
    }

    private var secondaryText: Color {
        store.isDarkMode ? Color(white: 0.50) : Color(white: 0.48)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Save location
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Save Location", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                SettingsGroup(isDark: store.isDarkMode) {
                    HStack(alignment: .center, spacing: 16) {
                        Ph.folder.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 15)
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
                            .frame(width: 30, height: 30)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 2.5) {
                            Text(store.downloadManager.downloadDirectory.lastPathComponent)
                                .font(store.leanUIFont.font(size: 13, weight: .medium))
                                .foregroundColor(primaryText)
                                .lineLimit(1)
                            Text(store.downloadManager.downloadDirectory.path)
                                .font(store.leanUIFont.font(size: 11))
                                .foregroundColor(secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 12)

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([store.downloadManager.downloadDirectory])
                        } label: {
                            Text("Show in Finder")
                                .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                                .foregroundColor(primaryText)
                                .padding(.horizontal, 11)
                                .frame(height: 27)
                                .background(
                                    store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Reveal the download folder in Finder")

                        Button {
                            chooseDownloadFolder()
                        } label: {
                            Text("Change...")
                                .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                                .foregroundColor(primaryText)
                                .padding(.horizontal, 11)
                                .frame(height: 27)
                                .background(
                                    store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Choose where downloaded files are saved")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            // File history
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SettingsHeaderLabel("Downloaded Files", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                    Spacer()
                    if store.downloadManager.downloads.contains(where: { !$0.isActive }) {
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                store.downloadManager.clearCompleted()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Ph.trash.fill
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 9.5, height: 9.5)
                                Text("Clear Finished")
                                    .font(store.leanUIFont.font(size: 11, weight: .medium))
                            }
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.60) : Color.black.opacity(0.55))
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !store.downloadManager.downloads.isEmpty {
                    HStack(spacing: 8) {
                        Ph.magnifyingGlass.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))

                        TextField("Search downloads...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(store.leanUIFont.font(size: 12.5))
                            .foregroundColor(primaryText)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Ph.xCircle.fill
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 12)
                                    .foregroundColor(secondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        store.isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 0.75)
                    )
                }

                if store.downloadManager.downloads.isEmpty {
                    VStack(spacing: 12) {
                        Ph.arrowCircleDown.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.30) : Color.black.opacity(0.30))
                        Text("No Downloads Yet")
                            .font(store.leanUIFont.font(size: 14, weight: .medium))
                            .foregroundColor(primaryText)
                        Text("Downloaded files are saved to your Downloads folder and listed here.")
                            .font(store.leanUIFont.font(size: 12))
                            .foregroundColor(secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Ph.magnifyingGlass.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.30) : Color.black.opacity(0.30))
                        Text("No Matches Found")
                            .font(store.leanUIFont.font(size: 14, weight: .medium))
                            .foregroundColor(primaryText)
                        Button {
                            searchText = ""
                        } label: {
                            Text("Clear Search")
                                .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                                .foregroundColor(primaryText)
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(
                                    store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    SettingsGroup(isDark: store.isDarkMode) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                SettingsRowDivider(isDark: store.isDarkMode, inset: 46)
                            }
                            DownloadSettingsRow(item: item, store: store)
                        }
                    }
                }
            }
        }
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where downloaded files are saved"
        panel.directoryURL = store.downloadManager.downloadDirectory
        if panel.runModal() == .OK, let url = panel.url {
            store.downloadManager.setDownloadDirectory(url)
        }
    }
}

// MARK: - Download Settings Row
private struct DownloadSettingsRow: View {
    let item: DownloadItem
    @ObservedObject var store: LeanStore
    @State private var isHovered = false
    @State private var showHoverActions = false
    @State private var hoverWorkItem: DispatchWorkItem?

    /// Delayed like the popover row: a double-click must never land on a
    /// Cancel button that just popped into layout.
    private func setHovered(_ hovering: Bool) {
        isHovered = hovering
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        if hovering {
            let work = DispatchWorkItem { showHoverActions = true }
            hoverWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        } else {
            showHoverActions = false
        }
    }

    private var subtitle: String {
        switch item.state {
        case .downloading:
            var parts = [DownloadFormat.progressText(received: item.receivedBytes, total: item.totalBytes)]
            let speed = DownloadFormat.speed(item.speedBytesPerSec)
            if speed != "—" { parts.append(speed) }
            return parts.joined(separator: " · ")
        case .completed:
            let when = item.endDate.map { DownloadFormat.relativeTime($0) } ?? "just now"
            let size = item.totalBytes > 0 ? DownloadFormat.fileSize(item.totalBytes) : DownloadFormat.fileSize(item.receivedBytes)
            return "\(size) · downloaded \(when)"
        case .failed:
            return item.errorDescription ?? "Download failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            DownloadFormat.icon(for: item.fileName).fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
                .frame(width: 32, height: 32)
                .background(
                    store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(store.leanUIFont.font(size: 13, weight: .medium))
                    .foregroundColor(store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(store.leanUIFont.font(size: 11))
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                    .lineLimit(1)

                if item.state == .downloading, item.totalBytes > 0 {
                    GeometryReader { geo in
                        Capsule()
                            .fill(store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                            .frame(height: 3)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(store.isDarkMode ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
                                    .frame(width: geo.size.width * CGFloat(item.fractionCompleted), height: 3)
                            }
                    }
                    .frame(height: 3)
                    .frame(maxWidth: 220)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                if item.state == .downloading {
                    if item.totalBytes > 0 {
                        Text("\(Int((item.fractionCompleted * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.40))
                    }
                    SettingsIconButton(icon: .x, help: "Cancel download", store: store) {
                        store.cancelDownload(id: item.id)
                    }
                    .opacity(showHoverActions ? 1 : 0)
                    .disabled(!showHoverActions)
                } else if showHoverActions {
                    SettingsIconButton(icon: .folder, help: "Show in Finder", store: store) {
                        store.revealDownload(item)
                    }
                    if item.state == .completed {
                        SettingsIconButton(icon: .arrowUpRight, help: "Open file", store: store) {
                            store.openDownload(item)
                        }
                    }
                    SettingsIconButton(icon: .trash, help: "Remove from list", store: store) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            store.downloadManager.removeDownload(id: item.id)
                        }
                    }
                }
            }
            .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(
            isHovered
                ? (store.isDarkMode ? Color.white.opacity(0.035) : Color.black.opacity(0.02))
                : Color.clear
        )
        .onHover(perform: setHovered)
        .help(item.destinationURL.path)
        .onTapGesture {
            if item.state == .completed {
                store.openDownload(item)
            } else {
                store.revealDownload(item)
            }
        }
        .onDisappear {
            hoverWorkItem?.cancel()
            hoverWorkItem = nil
        }
    }
}

private struct SettingsIconButton: View {
    let icon: Ph
    let help: String
    @ObservedObject var store: LeanStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon.uiIcon
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.7) : Color.black.opacity(0.65))
                .frame(width: 26, height: 26)
                .background(
                    store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(help)
    }
}

// MARK: - Sidebar Category Button
private struct SidebarCategoryButton: View {
    let category: SettingsCategory
    let isSelected: Bool
    let isDark: Bool
    let primaryText: Color
    let headingFont: (CGFloat) -> Font
    let onSelect: () -> Void

    @State private var isHovered = false

    private var iconColor: Color {
        if isSelected || isHovered { return primaryText }
        return isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.50)
    }

    private var labelColor: Color {
        if isSelected || isHovered { return primaryText }
        return isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.60)
    }

    private var rowFill: Color {
        if isSelected { return isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06) }
        if isHovered { return isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.035) }
        return Color.clear
    }

    private var rowStroke: Color? {
        guard isSelected else { return nil }
        return isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                category.icon.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundColor(iconColor)
                    .frame(width: 18)

                Text(category.rawValue)
                    .font(headingFont(13))
                    .foregroundColor(labelColor)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
            // Static background: no sliding pill, so the hit area never
            // moves between mouseDown and mouseUp.
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(rowFill)
                    .overlay(
                        Group {
                            if let stroke = rowStroke {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(stroke, lineWidth: 0.5)
                            }
                        }
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Category Button
private struct CompactCategoryButton: View {
    let category: SettingsCategory
    let isSelected: Bool
    let isDark: Bool
    let primaryText: Color
    let headingFont: (CGFloat) -> Font
    let onSelect: () -> Void

    @State private var isHovered = false

    private var labelColor: Color {
        if isSelected || isHovered { return primaryText }
        return isDark ? Color.white.opacity(0.50) : Color.black.opacity(0.50)
    }

    private var rowFill: Color {
        if isSelected { return isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.07) }
        if isHovered { return isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.035) }
        return Color.clear
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                category.icon.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                Text(category.rawValue)
            }
            .font(headingFont(12))
            .foregroundColor(labelColor)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

private struct PasswordManagerSection: View {
    @ObservedObject var store: LeanStore
    @State private var logins: [SavedPassword] = []
    @State private var searchText = ""
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isSaving = false
    @State private var revealed: [String: String] = [:]
    @State private var copiedID: String?
    @State private var pendingRemoval: SavedPassword?
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var filteredLogins: [SavedPassword] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return logins }
        return logins.filter { $0.host.localizedCaseInsensitiveContains(query) || $0.username.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Password Preferences
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Password settings", subtitle: "Autofill and credential capture", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                SettingsGroup(isDark: store.isDarkMode) {
                    CustomToggleRow(
                        title: "Offer to save passwords after sign-in",
                        subtitle: "Prompts you to remember new accounts and updated passwords",
                        isOn: $store.passwordSavePromptsEnabled,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont
                    )
                    SettingsRowDivider(isDark: store.isDarkMode)
                    CustomToggleRow(
                        title: "Offer matching sign-ins in page menus",
                        subtitle: "Shows saved credentials in login fields across web pages",
                        isOn: $store.passwordSuggestionsEnabled,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont
                    )
                }

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 11.5))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                    Text("Lean stores credentials securely in the macOS Keychain. Filling never submits a form automatically.")
                        .font(store.leanUIFont.font(size: 11.5))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                }
                .padding(.horizontal, 2)
            }

            // Saved Sign-ins Section
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Saved sign-ins (\(logins.count))", subtitle: "Accounts stored in your Keychain", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                if !logins.isEmpty {
                    // Minimal search bar
                    HStack(spacing: 8) {
                        Ph.magnifyingGlass.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.35))

                        TextField("Search by site or username…", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(store.leanUIFont.font(size: 12.5))
                            .foregroundColor(store.isDarkMode ? Color.white : Color.black)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Ph.xCircle.fill
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 12)
                                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(
                        store.isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(store.isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.06), lineWidth: 0.75)
                    )
                }

                SettingsGroup(isDark: store.isDarkMode) {
                    if logins.isEmpty {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(store.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.035))
                                    .frame(width: 42, height: 42)
                                Image(systemName: "key.fill")
                                    .font(.system(size: 17))
                                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.35))
                            }
                            VStack(spacing: 3) {
                                Text("No saved sign-ins yet")
                                    .font(store.leanUIFont.font(size: 13, weight: .medium))
                                    .foregroundColor(store.isDarkMode ? Color(white: 0.90) : Color(white: 0.15))
                                Text("Credentials you save while browsing or add below will appear here.")
                                    .font(store.leanUIFont.font(size: 11.5))
                                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .padding(.horizontal, 16)
                    } else if filteredLogins.isEmpty {
                        VStack(spacing: 6) {
                            Text("No matching sign-ins")
                                .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                                .foregroundColor(store.isDarkMode ? Color(white: 0.85) : Color(white: 0.20))
                            Text("No credentials found matching \"\(searchText)\".")
                                .font(store.leanUIFont.font(size: 11.5))
                                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                    } else {
                        ForEach(Array(filteredLogins.enumerated()), id: \.element.id) { index, login in
                            HStack(spacing: 12) {
                                SiteFaviconView(url: URL(string: login.origin), isDark: store.isDarkMode, size: 16)
                                    .frame(width: 28, height: 28)
                                    .background(store.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(store.isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.05), lineWidth: 0.5)
                                    )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(login.host)
                                        .font(store.leanUIFont.font(size: 13, weight: .medium))
                                        .foregroundColor(store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12))

                                    HStack(spacing: 6) {
                                        Text(login.username.isEmpty ? "No username" : login.username)
                                            .font(store.leanUIFont.font(size: 11.5))
                                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))

                                        Text("·")
                                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.3) : Color.black.opacity(0.3))

                                        if let secret = revealed[login.id] {
                                            Text(secret)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.85) : Color.black.opacity(0.80))
                                                .textSelection(.enabled)
                                        } else {
                                            Text("••••••••")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
                                        }
                                    }
                                }

                                Spacer(minLength: 8)

                                HStack(spacing: 6) {
                                    SettingsActionButton(revealed[login.id] == nil ? "Reveal" : "Hide", isDark: store.isDarkMode) {
                                        if revealed[login.id] != nil {
                                            revealed[login.id] = nil
                                        } else {
                                            read(login, reveal: true)
                                        }
                                    }
                                    SettingsActionButton(copiedID == login.id ? "Copied" : "Copy", isDark: store.isDarkMode) {
                                        read(login, reveal: false)
                                    }
                                    SettingsActionButton("Remove", isDark: store.isDarkMode, destructive: true) {
                                        pendingRemoval = login
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)

                            if index < filteredLogins.count - 1 {
                                SettingsRowDivider(isDark: store.isDarkMode, inset: 54)
                            }
                        }
                    }
                }
            }

            // Add a Sign-in Form
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Add a sign-in", subtitle: "Manually store an account in your Keychain", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                SettingsGroup(isDark: store.isDarkMode) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(spacing: 9) {
                            // Host Input
                            HStack(spacing: 10) {
                                Image(systemName: "globe")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.38))
                                    .frame(width: 16)

                                TextField("Website (e.g. github.com)", text: $host)
                                    .textFieldStyle(.plain)
                                    .font(store.leanUIFont.font(size: 12.5))
                                    .foregroundColor(store.isDarkMode ? Color.white : Color.black)

                                if !host.isEmpty {
                                    Button { host = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.75)
                            )

                            // Username Input
                            HStack(spacing: 10) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.38))
                                    .frame(width: 16)

                                TextField("Username or email", text: $username)
                                    .textFieldStyle(.plain)
                                    .font(store.leanUIFont.font(size: 12.5))
                                    .foregroundColor(store.isDarkMode ? Color.white : Color.black)

                                if !username.isEmpty {
                                    Button { username = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.75)
                            )

                            // Password Input
                            HStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.38))
                                    .frame(width: 16)

                                if isPasswordVisible {
                                    TextField("Password", text: $password)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 12.5, design: .monospaced))
                                        .foregroundColor(store.isDarkMode ? Color.white : Color.black)
                                } else {
                                    SecureField("Password", text: $password)
                                        .textFieldStyle(.plain)
                                        .font(store.leanUIFont.font(size: 12.5))
                                        .foregroundColor(store.isDarkMode ? Color.white : Color.black)
                                }

                                if !password.isEmpty {
                                    Button {
                                        isPasswordVisible.toggle()
                                    } label: {
                                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                            .font(.system(size: 11.5))
                                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(
                                store.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.75)
                            )
                        }

                        HStack {
                            if let successMessage {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                    Text(successMessage)
                                        .font(store.leanUIFont.font(size: 11.5))
                                        .foregroundColor(.green)
                                }
                            }
                            Spacer()
                            SettingsActionButton(isSaving ? "Saving…" : "Save to Keychain", isDark: store.isDarkMode, prominent: true, isLoading: isSaving) {
                                saveLogin()
                            }
                            .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || isSaving)
                        }
                    }
                    .padding(14)
                }
            }

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(store.leanUIFont.font(size: 11.5))
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 2)
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: PasswordVault.didChange)) { _ in reload() }
        .confirmationDialog("Remove this saved sign-in?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval {
                    if case .failure(let error) = PasswordVault.remove(pendingRemoval) {
                        errorMessage = error.localizedDescription
                    } else {
                        revealed.removeValue(forKey: pendingRemoval.id)
                    }
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            if let pendingRemoval {
                Text("Are you sure you want to remove the credentials for \"\(pendingRemoval.host)\"? This action will remove them from the macOS Keychain.")
            }
        }
        .onDisappear { revealed.removeAll() }
    }

    private func reload() {
        if case .success(let saved) = PasswordVault.all() {
            logins = saved
            errorMessage = nil
        } else {
            errorMessage = "Couldn't read saved sign-ins from the macOS Keychain."
        }
    }

    private func saveLogin() {
        var trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost.lowercased().hasPrefix("https://") {
            trimmedHost = String(trimmedHost.dropFirst(8))
        } else if trimmedHost.lowercased().hasPrefix("http://") {
            trimmedHost = String(trimmedHost.dropFirst(7))
        }
        if let slashIndex = trimmedHost.firstIndex(of: "/") {
            trimmedHost = String(trimmedHost[..<slashIndex])
        }
        guard let normalized = PasswordVault.normalizedHost(trimmedHost),
              let origin = URL(string: "https://\(normalized)") else {
            errorMessage = PasswordVault.VaultError.invalidOrigin.localizedDescription
            return
        }
        isSaving = true
        switch PasswordVault.save(origin: origin, username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password) {
        case .success:
            host = ""
            username = ""
            password = ""
            errorMessage = nil
            successMessage = "Saved to Keychain"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                successMessage = nil
            }
            reload()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func read(_ login: SavedPassword, reveal: Bool) {
        PasswordVault.authenticate(reason: "Access the saved sign-in for \(login.host)") { authenticated in
            guard authenticated else { return }
            switch PasswordVault.password(for: login) {
            case .success(let secret):
                if reveal {
                    revealed[login.id] = secret
                    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                        if revealed[login.id] == secret { revealed[login.id] = nil }
                    }
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(secret, forType: .string)
                    copiedID = login.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        if copiedID == login.id { copiedID = nil }
                    }
                }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }
}

@available(macOS 15.4, *)
private struct ExtensionsSettingsSection: View {
    @ObservedObject var store: LeanStore
    @StateObject private var manager = BrowserExtensionManager.shared
    @State private var pendingReview: BrowserExtensionManager.InstallationReview?
    @State private var selectedExtensionID: String? = nil
    @State private var isPreparing = false
    @State private var storeLink = ""
    @State private var isBackHovered = false
    @State private var isShowingRemoveConfirm = false

    var body: some View {
        Group {
            if let selectedID = selectedExtensionID,
               let item = manager.installed.first(where: { $0.id == selectedID }) {
                extensionDetailView(for: item)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
            } else {
                mainListView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .leading)),
                        removal: .opacity.combined(with: .move(edge: .trailing))
                    ))
            }
        }
        .sheet(item: $pendingReview) { review in
            ExtensionInstallReviewSheet(review: review, isDark: store.isDarkMode, uiFont: store.leanUIFont) {
                manager.cancelInstallation(review)
                pendingReview = nil
            } install: { permissions, hosts in
                await manager.install(review, permissions: permissions, hosts: hosts)
                pendingReview = nil
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Main List View
    private var mainListView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Add from Chrome Web Store Card
            SettingsGroup(isDark: store.isDarkMode) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Add from the Chrome Web Store")
                            .font(store.leanUIFont.font(size: 13, weight: .medium))
                        Spacer(minLength: 8)
                        SettingsActionButton("Open the Store", isDark: store.isDarkMode) {
                            if let url = URL(string: "https://chromewebstore.google.com/") { store.openURL(url) }
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Paste a link to an extension, or its id", text: $storeLink)
                            .textFieldStyle(.plain)
                            .font(store.leanUIFont.font(size: 12.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        SettingsActionButton(manager.isInstallingFromStore ? "Downloading…" : "Add", isDark: store.isDarkMode, prominent: true, isLoading: manager.isInstallingFromStore) {
                            Task {
                                if let review = await manager.prepareStoreInstallation(from: storeLink) {
                                    pendingReview = review
                                    storeLink = ""
                                }
                            }
                        }
                        .disabled(manager.isInstallingFromStore || ChromeWebStoreInstaller.extensionID(from: storeLink) == nil)
                    }
                    Text("Paste a Chrome Web Store URL or extension ID. Lean verifies the download before asking you to review its access.")
                        .font(store.leanUIFont.font(size: 11.5))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }

            // Installed Extensions Group
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Installed extensions", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                SettingsGroup(isDark: store.isDarkMode) {
                    if manager.installed.isEmpty {
                        Text("No extensions installed. Add an unpacked extension folder that contains manifest.json.")
                            .font(store.leanUIFont.font(size: 11.5))
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    } else {
                        ForEach(Array(manager.installed.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    extensionIconView(for: item.id, size: 32)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name)
                                            .font(store.leanUIFont.font(size: 13, weight: .medium))
                                            .foregroundColor(store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12))
                                        Text("Version \(item.version) · \(item.fromStore == true ? "Chrome Web Store" : "Unpacked extension")")
                                            .font(store.leanUIFont.font(size: 11))
                                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                                    }
                                    Spacer(minLength: 8)
                                    HStack(spacing: 10) {
                                        SettingsActionButton("Options", isDark: store.isDarkMode) {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                selectedExtensionID = item.id
                                            }
                                        }
                                        TactileSwitch(
                                            isOn: Binding(
                                                get: { item.enabled },
                                                set: { manager.setEnabled(item.id, to: $0) }
                                            ),
                                            isDark: store.isDarkMode
                                        )
                                    }
                                }
                                .padding(14)
                            }
                            if index < manager.installed.count - 1 {
                                SettingsRowDivider(isDark: store.isDarkMode, inset: 58)
                            }
                        }
                    }
                }
            }

            // Load Unpacked Extension Card
            SettingsGroup(isDark: store.isDarkMode) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Load an unpacked extension")
                            .font(store.leanUIFont.font(size: 13, weight: .medium))
                        Text("Choose a folder containing manifest.json. Lean copies it into its extension folder.")
                            .font(store.leanUIFont.font(size: 11.5))
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    SettingsActionButton(isPreparing ? "Reading…" : "Choose…", isDark: store.isDarkMode, isLoading: isPreparing) {
                        chooseExtensionFolder()
                    }
                    .disabled(isPreparing)
                }
                .padding(14)
            }

            if let errorMessage = manager.errorMessage {
                Text(errorMessage)
                    .font(store.leanUIFont.font(size: 11.5))
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }

            Text("Extensions require macOS 15.4 or later. Content scripts and WebKit-managed extension features can run, but toolbar popups and some browser APIs are not connected yet. Optional runtime permission requests are denied until you grant access here.")
                .font(store.leanUIFont.font(size: 11.5))
                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Extension Detail Stack Page
    private func extensionDetailView(for item: BrowserExtensionManager.Installed) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Back Button
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedExtensionID = nil
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Extensions")
                            .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                    }
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.78) : Color.black.opacity(0.72))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        isBackHovered ? (store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.055)) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .onHover { isBackHovered = $0 }

                Spacer()
            }
            .padding(.bottom, -6)

            // Extension Header Card
            SettingsGroup(isDark: store.isDarkMode) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        extensionIconView(for: item.id, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(store.leanUIFont.font(size: 15, weight: .semibold))
                                .foregroundColor(store.isDarkMode ? Color(white: 0.95) : Color(white: 0.10))
                            HStack(spacing: 6) {
                                Text("Version \(item.version)")
                                Text("·")
                                Text(item.fromStore == true ? "Chrome Web Store" : "Unpacked extension")
                                Text("·")
                                Text(manager.loadedIDs.contains(item.id) ? "Running" : (item.enabled ? "Active" : "Stopped"))
                                    .foregroundColor(manager.loadedIDs.contains(item.id) ? Color.green.opacity(0.85) : (store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48)))
                            }
                            .font(store.leanUIFont.font(size: 11))
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                        }
                        Spacer(minLength: 8)
                        TactileSwitch(
                            isOn: Binding(
                                get: { item.enabled },
                                set: { manager.setEnabled(item.id, to: $0) }
                            ),
                            isDark: store.isDarkMode
                        )
                    }

                    SettingsRowDivider(isDark: store.isDarkMode, inset: 0)

                    HStack(spacing: 8) {
                        SettingsActionButton("Reload", isDark: store.isDarkMode) {
                            manager.reload(item.id)
                        }
                        if item.fromStore == true {
                            SettingsActionButton("Store Page", isDark: store.isDarkMode) {
                                if let url = URL(string: "https://chromewebstore.google.com/detail/\(item.id)") {
                                    store.openURL(url)
                                }
                            }
                        } else {
                            SettingsActionButton("Reveal in Finder", isDark: store.isDarkMode) {
                                manager.revealInFinder(item.id)
                            }
                        }
                        if let optionsURL = manager.optionsPageURL(for: item.id) {
                            SettingsActionButton("Extension Options", isDark: store.isDarkMode) {
                                store.openURL(optionsURL)
                            }
                        }
                    }
                }
                .padding(16)
            }

            // Permissions & Site Access Section
            let hasPermissions = !item.requiredPermissions.isEmpty || !item.optionalPermissions.isEmpty || !item.requiredHosts.isEmpty || !item.optionalHosts.isEmpty
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Permissions & Site Access", subtitle: "Controls what data and web pages this extension can access", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                SettingsGroup(isDark: store.isDarkMode) {
                    if hasPermissions {
                        VStack(alignment: .leading, spacing: 0) {
                            if !item.requiredPermissions.isEmpty {
                                permissionSubheader("Requested permissions")
                                ForEach(item.requiredPermissions, id: \.self) { perm in
                                    CustomToggleRow(
                                        title: perm,
                                        isOn: Binding(
                                            get: { item.grantedPermissions.contains(perm) },
                                            set: { manager.setPermission(perm, enabled: $0, for: item.id) }
                                        ),
                                        isDark: store.isDarkMode,
                                        uiFont: store.leanUIFont
                                    )
                                }
                            }
                            if !item.optionalPermissions.isEmpty {
                                if !item.requiredPermissions.isEmpty { SettingsRowDivider(isDark: store.isDarkMode) }
                                permissionSubheader("Optional permissions")
                                ForEach(item.optionalPermissions, id: \.self) { perm in
                                    CustomToggleRow(
                                        title: perm,
                                        isOn: Binding(
                                            get: { item.grantedPermissions.contains(perm) },
                                            set: { manager.setPermission(perm, enabled: $0, for: item.id) }
                                        ),
                                        isDark: store.isDarkMode,
                                        uiFont: store.leanUIFont
                                    )
                                }
                            }
                            if !item.requiredHosts.isEmpty {
                                if !item.requiredPermissions.isEmpty || !item.optionalPermissions.isEmpty { SettingsRowDivider(isDark: store.isDarkMode) }
                                permissionSubheader("Requested site access")
                                ForEach(item.requiredHosts, id: \.self) { host in
                                    CustomToggleRow(
                                        title: host,
                                        isOn: Binding(
                                            get: { item.grantedHosts.contains(host) },
                                            set: { manager.setHost(host, enabled: $0, for: item.id) }
                                        ),
                                        isDark: store.isDarkMode,
                                        uiFont: store.leanUIFont
                                    )
                                }
                            }
                            if !item.optionalHosts.isEmpty {
                                if !item.requiredPermissions.isEmpty || !item.optionalPermissions.isEmpty || !item.requiredHosts.isEmpty { SettingsRowDivider(isDark: store.isDarkMode) }
                                permissionSubheader("Optional site access")
                                ForEach(item.optionalHosts, id: \.self) { host in
                                    CustomToggleRow(
                                        title: host,
                                        isOn: Binding(
                                            get: { item.grantedHosts.contains(host) },
                                            set: { manager.setHost(host, enabled: $0, for: item.id) }
                                        ),
                                        isDark: store.isDarkMode,
                                        uiFont: store.leanUIFont
                                    )
                                }
                            }
                        }
                    } else {
                        Text("This extension does not require any additional permissions or host access.")
                            .font(store.leanUIFont.font(size: 11.5))
                            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                }
            }

            // Diagnostics Section
            if let diagnostics = manager.errors[item.id], !diagnostics.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsHeaderLabel("Diagnostics", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                    SettingsGroup(isDark: store.isDarkMode) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                                Text(diagnostic)
                                    .font(store.leanUIFont.font(size: 11))
                                    .foregroundColor(.red)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(14)
                    }
                }
            }

            // Danger Zone Section
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Danger Zone", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                SettingsGroup(isDark: store.isDarkMode) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Remove Extension")
                                .font(store.leanUIFont.font(size: 13, weight: .medium))
                                .foregroundColor(store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12))
                            Text("Uninstall this extension and delete its files from Lean.")
                                .font(store.leanUIFont.font(size: 11.5))
                                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
                        }
                        Spacer(minLength: 8)
                        SettingsActionButton("Remove…", isDark: store.isDarkMode, destructive: true) {
                            isShowingRemoveConfirm = true
                        }
                    }
                    .padding(14)
                }
            }
            .confirmationDialog(
                "Remove \(item.name)?",
                isPresented: $isShowingRemoveConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove Extension", role: .destructive) {
                    manager.remove(item.id)
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedExtensionID = nil
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will delete \"\(item.name)\" and remove all of its data from Lean. This action cannot be undone.")
            }
        }
    }

    private func permissionSubheader(_ title: String) -> some View {
        Text(title)
            .font(store.leanUIFont.font(size: 11, weight: .medium))
            .foregroundColor(store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48))
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func extensionIconView(for id: String, size: CGFloat) -> some View {
        if let icon = manager.icon(for: id) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size > 32 ? 8 : 6, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size > 32 ? 8 : 6, style: .continuous)
                    .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.4) : Color.black.opacity(0.35))
            }
            .frame(width: size, height: size)
        }
    }

    private func chooseExtensionFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a local web extension"
        panel.message = "Select an unpacked extension folder containing manifest.json. Lean copies it into its local extension store."
        panel.prompt = "Review Extension"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        isPreparing = true
        Task {
            pendingReview = await manager.prepareInstallation(from: folder)
            isPreparing = false
        }
    }
}

@available(macOS 15.4, *)
private struct ExtensionInstallReviewSheet: View {
    let review: BrowserExtensionManager.InstallationReview
    let isDark: Bool
    let uiFont: LeanFont
    let cancel: () -> Void
    let install: (Set<String>, Set<String>) async -> Void

    @State private var grantedPermissions = Set<String>()
    @State private var grantedHosts = Set<String>()
    @State private var isInstalling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let icon = review.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Review extension")
                        .font(uiFont.font(size: 17, weight: .semibold))
                    Text("\(review.name) · version \(review.version)")
                        .font(uiFont.font(size: 12))
                        .foregroundColor(isDark ? Color.white.opacity(0.52) : Color.black.opacity(0.50))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    CustomChecklistRow(
                        title: "Select all permissions and sites",
                        isOn: Binding(
                            get: { allAccessSelected },
                            set: { selectAll in
                                grantedPermissions = selectAll ? allPermissions : []
                                grantedHosts = selectAll ? allHosts : []
                            }
                        ),
                        isDark: isDark,
                        uiFont: uiFont
                    )
                    .disabled(allPermissions.isEmpty && allHosts.isEmpty)
                    reviewChecklist("Requested permissions", values: review.requiredPermissions, selection: $grantedPermissions)
                    reviewChecklist("Optional permissions", values: review.optionalPermissions, selection: $grantedPermissions)
                    reviewChecklist("Requested site access", values: review.requiredHosts, selection: $grantedHosts)
                    reviewChecklist("Optional site access", values: review.optionalHosts, selection: $grantedHosts)
                    if !review.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("WebKit warnings")
                                .font(uiFont.font(size: 11.5, weight: .medium))
                            ForEach(Array(review.warnings.enumerated()), id: \.offset) { _, warning in
                                Text(warning)
                                    .font(uiFont.font(size: 11))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 340)
            HStack {
                Spacer()
                SettingsActionButton("Cancel", isDark: isDark, action: cancel)
                SettingsActionButton(isInstalling ? "Installing…" : "Install", isDark: isDark, prominent: true, isLoading: isInstalling) {
                    Task {
                        isInstalling = true
                        await install(grantedPermissions, grantedHosts)
                        isInstalling = false
                    }
                }
                .disabled(isInstalling)
            }
        }
        .padding(20)
        .frame(width: 480, height: 520)
        .background(isDark ? Color(white: 0.10) : Color(white: 0.98))
        .onAppear {
            grantedPermissions = Set(review.requiredPermissions)
            grantedHosts = Set(review.requiredHosts)
        }
    }

    private var allPermissions: Set<String> {
        Set(review.requiredPermissions + review.optionalPermissions)
    }

    private var allHosts: Set<String> {
        Set(review.requiredHosts + review.optionalHosts)
    }

    private var allAccessSelected: Bool {
        let hasAccess = !allPermissions.isEmpty || !allHosts.isEmpty
        return hasAccess && allPermissions.isSubset(of: grantedPermissions) && allHosts.isSubset(of: grantedHosts)
    }

    @ViewBuilder
    private func reviewChecklist(_ title: String, values: [String], selection: Binding<Set<String>>) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(uiFont.font(size: 11.5, weight: .medium))
                    .foregroundColor(isDark ? Color.white.opacity(0.52) : Color.black.opacity(0.50))
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                ForEach(values, id: \.self) { value in
                    CustomChecklistRow(
                        title: value,
                        isOn: Binding(
                            get: { selection.wrappedValue.contains(value) },
                            set: { isOn in
                                if isOn { selection.wrappedValue.insert(value) }
                                else { selection.wrappedValue.remove(value) }
                            }
                        ),
                        isDark: isDark,
                        uiFont: uiFont
                    )
                }
            }
            .background(isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
        }
    }
}

private struct ImportDataSection: View {
    @ObservedObject var store: LeanStore
    @State private var selectedBrowser = BrowserImportSource.chrome
    @State private var profilePreview: BrowserImportPreview?
    @State private var browserImportPreview: BrowserImportPreview?
    @State private var importBookmarks = true
    @State private var importHistory = true
    @State private var browserImportStage: BrowserImportStage = .access
    @State private var showsBrowserImportDialog = false
    @State private var isReadingBrowserData = false
    @State private var browserImportError: String?
    @State private var browserImportResult: String?
    @State private var credentialPreview: PasswordCSVPreview?
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Import from a browser", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                SettingsGroup(isDark: store.isDarkMode) {
                    VStack(alignment: .leading, spacing: 12) {
                        CustomSegmentedPicker(
                            options: BrowserImportSource.allCases.map { SegmentOption(id: $0.rawValue, label: $0.title) },
                            selectedId: selectedBrowser.rawValue,
                            isDark: store.isDarkMode,
                            uiFont: store.leanUIFont
                        ) { id in
                            guard let source = BrowserImportSource(rawValue: id) else { return }
                            selectedBrowser = source
                            profilePreview = nil
                            browserImportPreview = nil
                            browserImportError = nil
                            error = nil
                        }
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Bookmarks and history")
                                    .font(store.leanUIFont.font(size: 13, weight: .medium))
                                Text("Choose a browser. On first import, allow Lean to access its data folder; profiles are found automatically and that access is remembered.")
                                    .font(store.leanUIFont.font(size: 11.5))
                                    .foregroundColor(secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            SettingsActionButton(
                                "Import from \(selectedBrowser.title)",
                                isDark: store.isDarkMode,
                                prominent: true,
                                isLoading: isReadingBrowserData
                            ) {
                                importFromSelectedBrowser()
                            }
                        }
                    }
                    .padding(14)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("From an export file", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                SettingsGroup(isDark: store.isDarkMode) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Passwords (CSV)")
                                .font(store.leanUIFont.font(size: 13, weight: .medium))
                            Text("Import a CSV with URL, username, and password columns. Credentials are written to the macOS Keychain.")
                                .font(store.leanUIFont.font(size: 11.5))
                                .foregroundColor(secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        SettingsActionButton("Choose CSV…", isDark: store.isDarkMode) { choosePasswordFile() }
                    }
                    .padding(14)
                    SettingsRowDivider(isDark: store.isDarkMode)
                    HStack {
                        Text("Bookmarks JSON or history CSV (url, title, timestamp)")
                            .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                        Spacer()
                        SettingsActionButton("Bookmarks…", isDark: store.isDarkMode) { chooseBrowserExport(bookmarks: true) }
                        SettingsActionButton("History…", isDark: store.isDarkMode) { chooseBrowserExport(bookmarks: false) }
                    }
                    .padding(14)
                    if let credentialPreview {
                        SettingsRowDivider(isDark: store.isDarkMode)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(credentialPreview.credentials.count) credentials ready to import · \(credentialPreview.skippedRows) invalid rows")
                                    .font(store.leanUIFont.font(size: 11.5))
                                    .foregroundColor(secondaryText)
                                Text(credentialPreview.credentials.prefix(3).map { "\($0.host) · \($0.username)" }.joined(separator: ", "))
                                    .font(store.leanUIFont.font(size: 10.5))
                                    .foregroundColor(secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            SettingsActionButton("Cancel", isDark: store.isDarkMode) { self.credentialPreview = nil }
                            SettingsActionButton("Import", isDark: store.isDarkMode, prominent: true) {
                                let result = BrowserDataImporter.saveCredentials(credentialPreview.credentials)
                                let skipped = result.skipped + credentialPreview.skippedRows
                                message = "Imported \(result.saved) credentials; \(skipped) skipped."
                                error = nil
                                self.credentialPreview = nil
                            }
                        }
                        .padding(14)
                    }
                }
            }

            if !store.importedBookmarks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsHeaderLabel("Imported bookmarks", uiFont: store.leanUIFont, isDark: store.isDarkMode)
                    SettingsGroup(isDark: store.isDarkMode) {
                        ForEach(store.importedBookmarks) { bookmark in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.title)
                                        .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                                        .lineLimit(1)
                                    Text(bookmark.url.host ?? bookmark.url.absoluteString)
                                        .font(store.leanUIFont.font(size: 11))
                                        .foregroundColor(secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                SettingsActionButton("Open", isDark: store.isDarkMode) { store.openURL(bookmark.url) }
                                Button {
                                    store.deleteImportedBookmark(id: bookmark.id)
                                } label: {
                                    Ph.x.uiIcon
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove bookmark")
                                .help("Remove bookmark")
                            }
                            .padding(12)
                            if bookmark.id != store.importedBookmarks.last?.id {
                                SettingsRowDivider(isDark: store.isDarkMode)
                            }
                        }
                    }
                }
            }

            if let error {
                HStack(spacing: 10) {
                    Text(error).font(store.leanUIFont.font(size: 11.5)).foregroundColor(.red)
                    Spacer(minLength: 8)
                    SettingsActionButton("Dismiss", isDark: store.isDarkMode) { self.error = nil }
                }
            } else if let message {
                Text(message).font(store.leanUIFont.font(size: 11.5)).foregroundColor(secondaryText)
            }
        }
        .sheet(isPresented: $showsBrowserImportDialog) {
            BrowserImportProgressDialog(
                sourceTitle: selectedBrowser.title,
                isDark: store.isDarkMode,
                uiFont: store.leanUIFont,
                stage: $browserImportStage,
                preview: $browserImportPreview,
                includeBookmarks: $importBookmarks,
                includeHistory: $importHistory,
                errorMessage: $browserImportError,
                resultMessage: $browserImportResult,
                availableHistorySlots: max(0, 200 - store.historyItems.count),
                chooseFolder: chooseBrowserDataFolder,
                importSelected: importSelectedBrowserData,
                cancel: { showsBrowserImportDialog = false }
            )
        }
    }

    private var secondaryText: Color {
        store.isDarkMode ? Color.white.opacity(0.48) : Color.black.opacity(0.48)
    }

    private func importFromSelectedBrowser() {
        error = nil
        message = nil
        browserImportError = nil
        browserImportResult = nil
        browserImportPreview = nil
        showsBrowserImportDialog = true
        guard let data = UserDefaults.standard.data(forKey: selectedBrowser.bookmarkKey) else {
            browserImportStage = .access
            return
        }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                let renewed = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(renewed, forKey: selectedBrowser.bookmarkKey)
            }
            startBrowserScan(at: url)
        } catch {
            browserImportError = "Couldn't restore access to the saved \(selectedBrowser.title) folder. Choose it again."
            browserImportStage = .access
        }
    }

    private func startBrowserScan(at url: URL) {
        browserImportStage = .scanning
        isReadingBrowserData = true
        Task {
            do {
                let preview = try await Task.detached(priority: .userInitiated) {
                    let didAccess = url.startAccessingSecurityScopedResource()
                    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                    return try BrowserDataImporter.readProfiles(at: url)
                }.value
                browserImportPreview = preview
                importBookmarks = !preview.bookmarks.isEmpty
                importHistory = !preview.history.isEmpty
                browserImportStage = .selection
            } catch {
                browserImportError = error.localizedDescription
                browserImportStage = .failed
            }
            isReadingBrowserData = false
        }
    }

    private func importSelectedBrowserData() {
        guard let preview = browserImportPreview else { return }
        browserImportStage = .importing
        Task {
            await Task.yield()
            let selected = BrowserImportPreview(
                bookmarks: importBookmarks ? preview.bookmarks : [],
                history: importHistory ? preview.history : []
            )
            let imported = store.importBrowserData(selected)
            let result = "Imported \(imported.bookmarks) bookmarks and \(imported.history) history entries."
            browserImportResult = result
            message = result
            error = nil
            browserImportStage = .complete
        }
    }

    private func chooseBrowserDataFolder() {
        let panel = NSOpenPanel()
        panel.title = "Allow access to \(selectedBrowser.title) data"
        panel.message = "Select the browser data folder to import bookmarks and history. Lean finds profiles automatically."
        panel.prompt = "Allow Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedBrowser.userDataDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: selectedBrowser.bookmarkKey)
            browserImportError = nil
            startBrowserScan(at: url)
        } catch {
            browserImportError = error.localizedDescription
            browserImportStage = .access
        }
    }

    private func chooseBrowserExport(bookmarks: Bool) {
        let panel = NSOpenPanel()
        panel.title = bookmarks ? "Choose a bookmarks JSON export" : "Choose a history CSV export"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = bookmarks ? [.json] : [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        error = nil
        profilePreview = nil
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            if bookmarks {
                let parsed = try BrowserDataImporter.readBookmarkExport(Data(contentsOf: url))
                profilePreview = BrowserImportPreview(bookmarks: parsed, history: [])
                importBookmarks = true
                importHistory = false
            } else {
                let parsed = try BrowserDataImporter.readHistoryCSV(Data(contentsOf: url))
                guard !parsed.isEmpty else {
                    profilePreview = nil
                    error = "No usable history entries were found in that file."
                    return
                }
                profilePreview = BrowserImportPreview(bookmarks: [], history: parsed)
                importBookmarks = false
                importHistory = true
            }
        } catch {
            profilePreview = nil
            self.error = error.localizedDescription
        }
    }

    private func choosePasswordFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a password CSV export"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        error = nil
        credentialPreview = nil
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            credentialPreview = try BrowserDataImporter.readPasswordCSV(Data(contentsOf: url))
            if credentialPreview?.credentials.isEmpty == true {
                error = "No usable credentials were found; \(credentialPreview?.skippedRows ?? 0) rows were skipped."
                credentialPreview = nil
            }
        } catch {
            credentialPreview = nil
            self.error = error.localizedDescription
        }
    }
}
