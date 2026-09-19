import SwiftUI
import UniformTypeIdentifiers

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case topBar = "Top Bar"
    case appearance = "Appearance"
    case tabs = "Tabs"
    case browsing = "Browsing"
    case privacy = "Privacy"
    case history = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .topBar: return "menubar.dock.rectangle"
        case .appearance: return "paintpalette"
        case .tabs: return "square.stack.3d.forward.dottedline"
        case .browsing: return "globe"
        case .privacy: return "shield"
        case .history: return "clock"
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
        case .history: return "Recently visited pages"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: LeanStore
    @State private var selectedCategory: SettingsCategory = .general

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
        .preferredColorScheme(store.colorScheme)
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
                    .font(store.leanUIFont.font(size: 16, weight: .semibold))
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
                            Image(systemName: category.icon)
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(
                                    isSelected
                                        ? primaryText
                                        : (store.isDarkMode ? Color.white.opacity(0.55) : Color.black.opacity(0.50))
                                )
                                .frame(width: 18)

                            Text(category.rawValue)
                                .font(store.leanUIFont.font(size: 13, weight: isSelected ? .medium : .regular))
                                .foregroundColor(
                                    isSelected
                                        ? primaryText
                                        : (store.isDarkMode ? Color.white.opacity(0.65) : Color.black.opacity(0.60))
                                )

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(
                            isSelected
                                ? (store.isDarkMode ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Footer version
            Text("Lean Browser")
                .font(store.leanUIFont.font(size: 10.5, weight: .medium))
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
                            Image(systemName: category.icon)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            Text(category.rawValue)
                                .font(store.leanUIFont.font(size: 12, weight: isSelected ? .semibold : .medium))
                        }
                        .foregroundColor(
                            isSelected
                                ? primaryText
                                : (store.isDarkMode ? Color.white.opacity(0.50) : Color.black.opacity(0.50))
                        )
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            isSelected
                                ? (store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
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
                .font(store.leanUIFont.font(size: 20, weight: .semibold))
                .foregroundColor(primaryText)
                .tracking(-0.3)

            Text(selectedCategory.subtitle)
                .font(store.leanUIFont.font(size: 12))
                .foregroundColor(secondaryText)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Category Content Switcher
    @ViewBuilder
    private var contentForSelectedCategory: some View {
        switch selectedCategory {
        case .general:
            GeneralSection(store: store)
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
        case .history:
            HistorySection(store: store)
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
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(store.isDarkMode ? Color.white.opacity(0.40) : Color.black.opacity(0.40))

                TextField("Search history by title or domain...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(store.leanUIFont.font(size: 12.5))
                    .foregroundColor(store.isDarkMode ? Color.white : Color.black)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
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
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 9.5))
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
                                Image(systemName: "trash")
                                    .font(.system(size: 9.5))
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
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32, weight: .ultraLight))
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
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
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
                        Image(systemName: isCopied ? "checkmark" : "link")
                            .font(.system(size: 11, weight: .medium))
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
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .medium))
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
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
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

                SettingsRowDivider(isDark: store.isDarkMode)

                CustomToggleRow(
                    title: "Window frame",
                    subtitle: "Encase the web view in an elegant, minimal outer border with adaptive light/dark appearance.",
                    isOn: $store.enableWindowBorder,
                    isDark: store.isDarkMode,
                    uiFont: store.leanUIFont
                )

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
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .semibold))
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
                    Image(systemName: isShownShelf ? "tray" : "checkmark.circle")
                        .font(.system(size: 12))
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
                    Image(systemName: item.systemImage)
                        .font(.system(size: 13, weight: .medium))
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
                        Image(systemName: isShown ? "minus.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 9, weight: .bold))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Theme Selector
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Interface Theme", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                CustomSegmentedPicker(
                    options: [
                        SegmentOption(id: AppTheme.light.rawValue, label: "Light", icon: "sun.max.fill"),
                        SegmentOption(id: AppTheme.dark.rawValue, label: "Dark", icon: "moon.fill"),
                        SegmentOption(id: AppTheme.system.rawValue, label: "System", icon: "circle.lefthalf.filled")
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
                SettingsHeaderLabel("Typography", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                SettingsGroup(isDark: store.isDarkMode) {
                    FontPickerRow(
                        title: "Lean UI",
                        subtitle: "Typeface applied to tabs, omnibar, and browser controls",
                        selection: $store.leanUIFont,
                        uiFont: store.leanUIFont,
                        isDark: store.isDarkMode
                    )

                    SettingsRowDivider(isDark: store.isDarkMode)

                    FontPickerRow(
                        title: "Web pages",
                        subtitle: "Typeface override applied to readable webpage text",
                        selection: $store.webPageFont,
                        uiFont: store.leanUIFont,
                        isDark: store.isDarkMode
                    )
                }
            }
        }
    }
}

// MARK: - 4. Tabs Section
private struct TabsSection: View {
    @ObservedObject var store: LeanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Tab Display Mode
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Tab Display Style", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                CustomSegmentedPicker(
                    options: [
                        SegmentOption(id: TabDisplayMode.textOnly.rawValue, label: "Text Only", icon: "text.alignleft"),
                        SegmentOption(id: TabDisplayMode.iconOnly.rawValue, label: "Icon Only", icon: "square.grid.2x2"),
                        SegmentOption(id: TabDisplayMode.hybrid.rawValue, label: "Hybrid", icon: "rectangle.badge.checkmark")
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
                        SegmentOption(id: ScrollbarStyle.hidden.rawValue, label: "Hidden", icon: "eye.slash"),
                        SegmentOption(id: ScrollbarStyle.thin.rawValue, label: "Thin", icon: "line.3.horizontal"),
                        SegmentOption(id: ScrollbarStyle.normal.rawValue, label: "Default", icon: "slider.vertical.3")
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
    @State private var historyCleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Search & Protection
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeaderLabel("Search & Protection", uiFont: store.leanUIFont, isDark: store.isDarkMode)

                SettingsGroup(isDark: store.isDarkMode) {
                    // Search Engine
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2.5) {
                            Text("Default search engine")
                                .font(store.leanUIFont.font(size: 13, weight: .medium))
                                .foregroundColor(primaryText)
                            Text("Queries entered into the omnibar are directed to this engine")
                                .font(store.leanUIFont.font(size: 11.5))
                                .foregroundColor(secondaryText)
                        }

                        Spacer(minLength: 16)

                        Picker("Default search engine", selection: $store.searchEngine) {
                            ForEach(SearchEngine.allCases) { engine in
                                Text(engine.name).tag(engine)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    SettingsRowDivider(isDark: store.isDarkMode)

                    CustomToggleRow(
                        title: "Tracker & ad filtering",
                        subtitle: "Block common ad networks, trackers, and invasive banners.",
                        isOn: $store.adBlockingEnabled,
                        isDark: store.isDarkMode,
                        uiFont: store.leanUIFont
                    )
                }
            }

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
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
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

    private var primaryText: Color {
        store.isDarkMode ? Color(white: 0.94) : Color(white: 0.12)
    }

    private var secondaryText: Color {
        store.isDarkMode ? Color(white: 0.50) : Color(white: 0.48)
    }
}
