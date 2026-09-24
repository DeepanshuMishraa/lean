import SwiftUI
import AppKit

struct BookmarksPaletteView: View {
    @ObservedObject var store: LeanStore

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @FocusState private var isFieldFocused: Bool
    @FocusState private var isNewFolderFocused: Bool

    // Folder navigation
    private var allFolders: [String] {
        var list = [BookmarkFolder.allFolder, BookmarkFolder.defaultFolder]
        for f in store.bookmarkFolders {
            if f != BookmarkFolder.defaultFolder && f != BookmarkFolder.allFolder && !list.contains(f) {
                list.append(f)
            }
        }
        return list
    }

    private var currentFolderIndex: Int {
        allFolders.firstIndex(of: store.selectedBookmarkFolder) ?? 0
    }

    // Filtered bookmarks
    private var filteredBookmarks: [BookmarkItem] {
        let inFolder: [BookmarkItem]
        if store.selectedBookmarkFolder == BookmarkFolder.allFolder {
            inFolder = store.bookmarks
        } else {
            inFolder = store.bookmarks.filter { $0.folder == store.selectedBookmarkFolder }
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmedQuery.isEmpty {
            return inFolder
        }

        return inFolder.filter { item in
            item.title.lowercased().contains(trimmedQuery) ||
            item.url.absoluteString.lowercased().contains(trimmedQuery) ||
            item.host.lowercased().contains(trimmedQuery) ||
            item.folder.lowercased().contains(trimmedQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            folderStripView

            Divider()
                .opacity(store.isDarkMode ? 0.10 : 0.06)

            if filteredBookmarks.isEmpty {
                emptyStateView
            } else {
                bookmarksListView
            }
        }
        .frame(width: store.scaled(560))
        .background(paletteBackground)
        .overlay(paletteBorder)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(
            color: Color.black.opacity(store.isDarkMode ? 0.36 : 0.10),
            radius: 20,
            x: 0,
            y: 8
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        store.bookmarksPaletteFrame = geo.frame(in: .global)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        store.bookmarksPaletteFrame = newFrame
                    }
            }
        )
        .onAppear {
            selectedIndex = 0
            requestFieldFocus()
        }
        .onChange(of: store.selectedBookmarkFolder) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    // MARK: - Minimal Search Header
    private var headerView: some View {
        HStack(spacing: 10) {
            Ph.magnifyingGlass.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: store.scaled(13), height: store.scaled(13))
                .foregroundColor(store.adaptiveTheme.secondaryText)

            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("Search bookmarks...")
                        .font(store.bodyFont(size: 13.5))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.32) : Color.black.opacity(0.32))
                        .allowsHitTesting(false)
                }

                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .font(store.bodyFont(size: 13.5))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                    .focused($isFieldFocused)
                    .onSubmit {
                        submitCurrent()
                    }
                    .onKeyPress(.downArrow) {
                        if !filteredBookmarks.isEmpty {
                            selectedIndex = min(selectedIndex + 1, filteredBookmarks.count - 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        if selectedIndex > 0 {
                            selectedIndex -= 1
                        }
                        return .handled
                    }
                    .onKeyPress(.leftArrow) {
                        switchFolder(offset: -1)
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        switchFolder(offset: 1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        store.dismissBookmarks()
                        return .handled
                    }
            }
            .clipped()

            Spacer(minLength: 4)

            Text("esc")
                .font(store.bodyFont(size: 9.5))
                .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.6))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 0.75)
                )
        }
        .padding(.horizontal, store.scaled(14))
        .frame(height: store.scaled(44))
    }

    // MARK: - Sleek Folder Strip
    private var folderStripView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(allFolders, id: \.self) { folder in
                        folderSegment(folder: folder)
                            .id(folder)
                    }

                    if isCreatingFolder {
                        inlineFolderCreator
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                                isCreatingFolder = true
                                newFolderName = ""
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    isNewFolderFocused = true
                                }
                            }
                        } label: {
                            Ph.plus.bold
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 9, height: 9)
                                .foregroundColor(store.adaptiveTheme.secondaryText)
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(store.isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("New Folder")
                    }
                }
                .padding(.horizontal, store.scaled(12))
                .padding(.bottom, store.scaled(7))
            }
            .onChange(of: store.selectedBookmarkFolder) { _, newFolder in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                    proxy.scrollTo(newFolder, anchor: .center)
                }
            }
        }
    }

    private func folderSegment(folder: String) -> some View {
        let isSelected = store.selectedBookmarkFolder == folder
        let textColor = isSelected ? (store.isDarkMode ? Color.white : Color.black) : store.adaptiveTheme.secondaryText
        let bgColor = isSelected
            ? (store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
            : Color.clear

        return Button {
            withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                store.selectedBookmarkFolder = folder
            }
        } label: {
            HStack(spacing: 4) {
                if folder == BookmarkFolder.defaultFolder {
                    Ph.star.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 10, height: 10)
                        .foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.22))
                }

                Text(folder)
                    .font(store.bodyFont(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundColor(textColor)
            }
            .padding(.horizontal, store.scaled(8))
            .padding(.vertical, store.scaled(4))
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(bgColor)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if folder != BookmarkFolder.allFolder && folder != BookmarkFolder.defaultFolder {
                Button("Delete Folder") {
                    store.deleteBookmarkFolder(folder)
                }
            }
        }
    }

    // Inline new folder creator input
    private var inlineFolderCreator: some View {
        HStack(spacing: 4) {
            TextField("Name...", text: $newFolderName)
                .textFieldStyle(.plain)
                .font(store.bodyFont(size: 11))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .focused($isNewFolderFocused)
                .frame(width: store.scaled(75))
                .onSubmit {
                    commitNewFolder()
                }
                .onKeyPress(.escape) {
                    cancelNewFolder()
                    return .handled
                }

            Button {
                commitNewFolder()
            } label: {
                Ph.check.bold
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 8, height: 8)
                    .foregroundColor(store.adaptiveTheme.primaryText)
            }
            .buttonStyle(.plain)

            Button {
                cancelNewFolder()
            } label: {
                Ph.x.bold
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 7, height: 7)
                    .foregroundColor(store.adaptiveTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(store.isDarkMode ? Color.white.opacity(0.16) : Color.black.opacity(0.12), lineWidth: 0.75)
        )
    }

    private func commitNewFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.addBookmarkFolder(trimmed)
            store.selectedBookmarkFolder = trimmed
        }
        isCreatingFolder = false
        newFolderName = ""
        requestFieldFocus()
    }

    private func cancelNewFolder() {
        isCreatingFolder = false
        newFolderName = ""
        requestFieldFocus()
    }

    private func switchFolder(offset: Int) {
        let count = allFolders.count
        guard count > 0 else { return }
        var nextIndex = currentFolderIndex + offset
        if nextIndex < 0 { nextIndex = count - 1 }
        if nextIndex >= count { nextIndex = 0 }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            store.selectedBookmarkFolder = allFolders[nextIndex]
        }
    }

    // MARK: - Bookmarks List
    private var bookmarksListView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    ForEach(Array(filteredBookmarks.enumerated()), id: \.element.id) { index, item in
                        BookmarkRow(
                            item: item,
                            isSelected: index == selectedIndex,
                            showFolderBadge: store.selectedBookmarkFolder == BookmarkFolder.allFolder,
                            store: store,
                            onOpen: { openBookmark(item) },
                            onOpenInNewTab: { openBookmarkInNewTab(item) },
                            onOpenSplit: { openBookmarkInSplit(item) },
                            onDelete: { deleteBookmark(item) },
                            onHover: { selectedIndex = index }
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, store.scaled(6))
                .padding(.vertical, store.scaled(5))
            }
            .frame(maxHeight: store.scaled(300))
            .onChange(of: selectedIndex) { _, newIndex in
                if filteredBookmarks.indices.contains(newIndex) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(filteredBookmarks[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 6) {
            Text(query.isEmpty ? "No bookmarks here" : "No bookmarks found")
                .font(store.bodyFont(size: 12.5, weight: .medium))
                .foregroundColor(store.adaptiveTheme.primaryText)

            Text(query.isEmpty ? "Press ⌘D on any tab to save it" : "Try searching something else")
                .font(store.bodyFont(size: 11))
                .foregroundColor(store.adaptiveTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, store.scaled(32))
    }

    // MARK: - Actions
    private func submitCurrent() {
        if filteredBookmarks.indices.contains(selectedIndex) {
            let item = filteredBookmarks[selectedIndex]
            if NSEvent.modifierFlags.contains(.command) {
                openBookmarkInNewTab(item)
            } else if NSEvent.modifierFlags.contains(.option) {
                openBookmarkInSplit(item)
            } else {
                openBookmark(item)
            }
        }
    }

    private func openBookmark(_ item: BookmarkItem) {
        store.dismissBookmarks()
        if store.selectedTab?.url != nil {
            store.selectedTab?.load(item.url)
        } else {
            store.newTab(url: item.url)
        }
    }

    private func openBookmarkInNewTab(_ item: BookmarkItem) {
        store.dismissBookmarks()
        store.newTab(url: item.url)
    }

    private func openBookmarkInSplit(_ item: BookmarkItem) {
        store.dismissBookmarks()
        let tab = store.createTab(url: item.url)
        if let selected = store.selectedTab {
            if selected.isSplit {
                store.addTabToActiveSplit(tab)
            } else {
                store.openTabAsSplit(selected)
                store.addTabToActiveSplit(tab)
            }
        } else {
            store.newTab(url: item.url)
        }
    }

    private func deleteBookmark(_ item: BookmarkItem) {
        withAnimation(.easeOut(duration: 0.14)) {
            store.deleteBookmark(id: item.id)
            if selectedIndex >= filteredBookmarks.count {
                selectedIndex = max(0, filteredBookmarks.count - 1)
            }
        }
    }

    private func requestFieldFocus() {
        isFieldFocused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFieldFocused = true
        }
    }

    // MARK: - Styling Helpers
    private var paletteBackground: some View {
        VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
            .background(store.themeColors.omnibarBackground)
    }

    private var paletteBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(store.themeColors.omnibarBorder, lineWidth: 0.75)
    }
}

// MARK: - Sleek Minimal Bookmark Row
struct BookmarkRow: View {
    let item: BookmarkItem
    let isSelected: Bool
    let showFolderBadge: Bool
    @ObservedObject var store: LeanStore

    let onOpen: () -> Void
    let onOpenInNewTab: () -> Void
    let onOpenSplit: () -> Void
    let onDelete: () -> Void
    let onHover: () -> Void

    @State private var isHovered = false

    private var rowBgColor: Color {
        if isSelected {
            return store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
        }
        if isHovered {
            return store.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
        }
        return Color.clear
    }

    var body: some View {
        HStack(spacing: 9) {
            SiteFaviconView(
                url: item.url,
                isDark: store.isDarkMode,
                size: 15
            )
            .frame(width: 16, height: 16)

            Text(item.title)
                .font(store.bodyFont(size: 12.5, weight: isSelected ? .medium : .regular))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .lineLimit(1)

            Text(item.host)
                .font(store.bodyFont(size: 11))
                .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.8))
                .lineLimit(1)

            Spacer(minLength: 4)

            if showFolderBadge && item.folder != BookmarkFolder.defaultFolder {
                Text(item.folder)
                    .font(store.bodyFont(size: 9.5))
                    .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(store.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    )
            }

            if isHovered || isSelected {
                HStack(spacing: 2) {
                    Button {
                        onOpenInNewTab()
                    } label: {
                        Ph.arrowSquareOut.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10, height: 10)
                            .foregroundColor(store.adaptiveTheme.secondaryText)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Open in New Tab (⌘↩)")

                    Button {
                        onDelete()
                    } label: {
                        Ph.trash.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10, height: 10)
                            .foregroundColor(Color.red.opacity(0.7))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, store.scaled(8))
        .padding(.vertical, store.scaled(5.5))
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowBgColor)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                onHover()
            }
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Open in New Tab") { onOpenInNewTab() }
            Button("Open in Split View") { onOpenSplit() }
            Divider()
            Menu("Move to Folder") {
                ForEach(store.bookmarkFolders, id: \.self) { folderName in
                    Button(folderName) {
                        store.moveBookmark(id: item.id, to: folderName)
                    }
                }
            }
            Divider()
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
            }
            Divider()
            Button("Delete Bookmark", role: .destructive) {
                onDelete()
            }
        }
    }
}
