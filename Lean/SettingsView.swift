import AppKit
import PhosphorSwift
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

    var id: String { rawValue }

    var icon: Ph {
        switch self {
        case .general: return .slidersHorizontal
        case .topBar: return .layout
        case .appearance: return .palette
        case .tabs: return .tabs
        case .browsing: return .globe
        case .privacy: return .shield
        case .shortcuts: return .command
        case .history: return .clock
        case .downloads: return .arrowCircleDown
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
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: LeanStore
    @ObservedObject var updater: AppUpdater
    @State private var selectedCategory: SettingsCategory = .general
    @StateObject private var dropdownState = DropdownMenuState()
    @Namespace private var sidebarAnimation
    @Namespace private var compactAnimation

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
                    let isSelected = category == selectedCategory
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 10) {
                            category.icon.fill
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .foregroundColor(
                                    isSelected
                                        ? primaryText
                                        : (store.isDarkMode ? Color.white.opacity(0.55) : Color.black.opacity(0.50))
                                )
                                .frame(width: 18)

                            Text(category.rawValue)
                                .font(store.headingFont(size: 13))
                                .foregroundColor(
                                    isSelected
                                        ? primaryText
                                        : (store.isDarkMode ? Color.white.opacity(0.65) : Color.black.opacity(0.60))
                                )

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(store.isDarkMode ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 0.5)
                                    )
                                    .matchedGeometryEffect(id: "activeSidebarCategory", in: sidebarAnimation)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                    let isSelected = category == selectedCategory
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 6) {
                            category.icon.fill
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                            Text(category.rawValue)
                        }
                        .font(store.headingFont(size: 12))
                        .foregroundColor(
                            isSelected
                                ? primaryText
                                : (store.isDarkMode ? Color.white.opacity(0.50) : Color.black.opacity(0.50))
                        )
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05), lineWidth: 0.5)
                                    )
                                    .matchedGeometryEffect(id: "activeCompactCategory", in: compactAnimation)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
                        subtitle: "Typeface override applied to readable webpage text",
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
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.tabLayout = .top
                }
            }

            TabLayoutCard(
                layout: .sidebar,
                isSelected: store.tabLayout == .sidebar,
                isDark: store.isDarkMode,
                uiFont: store.leanUIFont
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.tabLayout = .sidebar
                }
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
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
                .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isSelected)

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
            // Rendering Engine — WebKit default, CEF opt-in. Switching restarts Lean.
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Rendering Engine", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                CustomSegmentedPicker(
                    options: [
                        SegmentOption(id: BrowserEngineKind.webKit.rawValue, label: "WebKit", icon: .globe),
                        SegmentOption(id: BrowserEngineKind.cef.rawValue, label: "Chromium", icon: .cpu)
                    ],
                    selectedId: store.engineKind.rawValue,
                    isDark: store.isDarkMode,
                    uiFont: store.leanUIFont
                ) { newId in
                    if let kind = BrowserEngineKind(rawValue: newId) {
                        store.requestEngineChange(kind)
                    }
                }

                Text(engineFootnote)
                    .font(store.leanUIFont.font(size: 11.5))
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
            }

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

    private var engineFootnote: String {
        let engineName: String = {
            switch store.engineKind {
            case .webKit: return "System WebKit · default, no bundled engine."
            case .cef:
                if CEFIntegration.isAvailable() {
                    return "Chromium (CEF) · bundled engine, broader site compatibility."
                }
                return "Chromium selected · framework not bundled in this build (see docs/CEF.md)."
            }
        }()
        return engineName + " Switching engines restarts Lean; open tabs are restored."
    }
}

// MARK: - 6. Privacy & Data Section
private struct PrivacySection: View {
    @ObservedObject var store: LeanStore
    @EnvironmentObject private var dropdownState: DropdownMenuState
    @State private var historyCleared = false
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
                        subtitle: "Built-in blocking powered by uBlock Origin filter lists (EasyList, EasyPrivacy, uBlock filters).",
                        isOn: $store.adBlockingEnabled,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont
                    )

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

            // Data Management
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Data Management", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                SettingsGroup(isDark: store.isDarkMode) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2.5) {
                            Text("Browsing history & cache")
                                .font(store.leanUIFont.font(size: 13, weight: .medium))
                                .foregroundColor(primaryText)
                            Text("Purge session history, recently closed tabs, and address match cache")
                                .font(store.leanUIFont.font(size: 11.5))
                                .foregroundColor(secondaryText)
                        }

                        Spacer(minLength: 16)

                        if historyCleared {
                            HStack(spacing: 4) {
                                Ph.check.bold
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 10, height: 10)
                                Text("Cleared")
                                    .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                            }
                            .foregroundColor(Color(red: 48/255, green: 209/255, blue: 88/255))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .transition(.opacity)
                        } else {
                            Button {
                                store.clearHistory()
                                withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                                    historyCleared = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        historyCleared = false
                                    }
                                }
                            } label: {
                                Text("Clear Data")
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
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
            icon.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.7) : Color.black.opacity(0.65))
                .frame(width: 26, height: 26)
                .background(
                    store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
