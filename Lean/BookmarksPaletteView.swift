import SwiftUI
import AppKit

struct BookmarksPaletteView: View {
    @ObservedObject var store: LeanStore

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var isKeyboardNavigating = false
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
                .opacity(store.isDarkMode ? 0.12 : 0.07)

            if filteredBookmarks.isEmpty {
                emptyStateView
            } else {
                bookmarksListView
            }
        }
        .frame(width: store.scaled(580))
        .background(paletteBackground)
        .overlay(paletteBorder)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(
            color: Color.black.opacity(store.isDarkMode ? 0.40 : 0.12),
            radius: 24,
            x: 0,
            y: 10
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
        HStack(spacing: 12) {
            LeanIcon.magnifyingGlass.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15)
                .foregroundColor(store.adaptiveTheme.secondaryText)

            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("Search bookmarks...")
                        .font(store.bodyFont(size: 14))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
                        .allowsHitTesting(false)
                }

                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .font(store.bodyFont(size: 14))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                    .focused($isFieldFocused)
                    .onSubmit {
                        submitCurrent()
                    }
                    .onKeyPress(.downArrow) {
                        isKeyboardNavigating = true
                        if !filteredBookmarks.isEmpty {
                            selectedIndex = min(selectedIndex + 1, filteredBookmarks.count - 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        isKeyboardNavigating = true
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
                    .onKeyPress(.delete) {
                        deleteCurrentSelected()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        store.dismissBookmarks()
                        return .handled
                    }
            }
            .clipped()

            Spacer(minLength: 4)

            Text("ESC")
                .font(store.bodyFont(size: 9.5, weight: .medium))
                .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.7))
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.10), lineWidth: 0.75)
                )
        }
        .padding(.horizontal, store.scaled(16))
        .frame(height: store.scaled(48))
    }

    // MARK: - Sleek Folder Strip
    private var folderStripView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
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
                            HStack(spacing: 0) {
                                LeanIcon.plus.bold
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 13, height: 13)
                                    .foregroundColor(store.adaptiveTheme.secondaryText)
                            }
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.07), lineWidth: 0.75)
                            )
                        }
                        .buttonStyle(PlainHoverButtonStyle())
                        .help("New Folder")
                    }
                }
                .padding(.horizontal, store.scaled(14))
                .padding(.bottom, store.scaled(9))
                .padding(.top, store.scaled(2))
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
            ? (store.isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
            : Color.clear

        return Button {
            withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                store.selectedBookmarkFolder = folder
            }
        } label: {
            HStack(spacing: 6) {
                if folder == BookmarkFolder.allFolder {
                    LeanIcon.bookmarkSimple.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .foregroundColor(isSelected ? (store.isDarkMode ? Color.white : Color.black) : store.adaptiveTheme.secondaryText)
                } else if folder == BookmarkFolder.defaultFolder {
                    LeanIcon.star.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.22))
                } else {
                    LeanIcon.folder.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .foregroundColor(isSelected ? (store.isDarkMode ? Color.white : Color.black) : store.adaptiveTheme.secondaryText)
                }

                Text(folder)
                    .font(store.bodyFont(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(textColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? (store.isDarkMode ? Color.white.opacity(0.16) : Color.black.opacity(0.10)) : Color.clear, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if folder != BookmarkFolder.allFolder && folder != BookmarkFolder.defaultFolder {
                Button("Delete Folder", role: .destructive) {
                    store.deleteBookmarkFolder(folder)
                }
            }
        }
    }

    private var inlineFolderCreator: some View {
        HStack(spacing: 6) {
            LeanIcon.folderPlus.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 13, height: 13)
                .foregroundColor(store.adaptiveTheme.primaryText)

            TextField("Folder name...", text: $newFolderName)
                .textFieldStyle(.plain)
                .font(store.bodyFont(size: 12))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .frame(width: 100)
                .focused($isNewFolderFocused)
                .onSubmit {
                    commitInlineFolder()
                }

            Button {
                commitInlineFolder()
            } label: {
                Text("Add")
                    .font(store.bodyFont(size: 11, weight: .semibold))
                    .foregroundColor(store.isDarkMode ? Color.black : Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(store.isDarkMode ? Color.white : Color.black)
                    )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                    isCreatingFolder = false
                    newFolderName = ""
                    requestFieldFocus()
                }
            } label: {
                LeanIcon.x.bold
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 9, height: 9)
                    .foregroundColor(store.adaptiveTheme.secondaryText)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(store.isDarkMode ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 0.75)
        )
    }

    private func commitInlineFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.addBookmarkFolder(trimmed)
            store.selectedBookmarkFolder = trimmed
        }
        withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
            isCreatingFolder = false
            newFolderName = ""
            requestFieldFocus()
        }
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
                LazyVStack(spacing: 2) {
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
                            onHover: {
                                isKeyboardNavigating = false
                                selectedIndex = index
                            }
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, store.scaled(8))
                .padding(.vertical, store.scaled(6))
            }
            .frame(maxHeight: store.scaled(320))
            .onChange(of: selectedIndex) { _, newIndex in
                guard isKeyboardNavigating else { return }
                if filteredBookmarks.indices.contains(newIndex) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(filteredBookmarks[newIndex].id, anchor: nil)
                    }
                }
            }
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 7) {
            Text(query.isEmpty ? "No bookmarks in this folder" : "No matching bookmarks")
                .font(store.headingFont(size: 13, weight: .medium))
                .foregroundColor(store.adaptiveTheme.primaryText)

            Text(query.isEmpty ? "Press ⌘D on any web page to bookmark it" : "Try searching for a different keyword or domain")
                .font(store.bodyFont(size: 11.5))
                .foregroundColor(store.adaptiveTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, store.scaled(36))
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

    private func deleteCurrentSelected() {
        if filteredBookmarks.indices.contains(selectedIndex) {
            let item = filteredBookmarks[selectedIndex]
            deleteBookmark(item)
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
    @State private var isOpenHovered = false
    @State private var isDeleteHovered = false

    private var rowBgColor: Color {
        if isSelected {
            return store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
        }
        if isHovered {
            return store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.03)
        }
        return Color.clear
    }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
                    .frame(width: 24, height: 24)

                SiteFaviconView(
                    url: item.url,
                    isDark: store.isDarkMode,
                    size: 16
                )
            }

            Text(item.title)
                .font(store.bodyFont(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .lineLimit(1)

            Text(item.host)
                .font(store.bodyFont(size: 11.5))
                .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.75))
                .lineLimit(1)

            Spacer(minLength: 8)

            if showFolderBadge && item.folder != BookmarkFolder.defaultFolder {
                HStack(spacing: 4) {
                    LeanIcon.folder.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 10, height: 10)
                        .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.7))

                    Text(item.folder)
                        .font(store.bodyFont(size: 10, weight: .medium))
                        .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.8))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                )
            }

            if isHovered || isSelected {
                HStack(spacing: 4) {
                    Button {
                        onOpenInNewTab()
                    } label: {
                        LeanIcon.arrowSquareOut.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundColor(isOpenHovered ? store.adaptiveTheme.primaryText : store.adaptiveTheme.secondaryText)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                    .fill(isOpenHovered ? (store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.07)) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { isOpenHovered = $0 }
                    .help("Open in New Tab (⌘↩)")

                    Button {
                        onDelete()
                    } label: {
                        LeanIcon.trash.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundColor(isDeleteHovered ? Color.red : Color.red.opacity(0.75))
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                    .fill(isDeleteHovered ? Color.red.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { isDeleteHovered = $0 }
                    .help("Delete (⌫)")
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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

// MARK: - Plain hover button style
private struct PlainHoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isHovered ? 0.8 : 1.0)
            .onHover { isHovered = $0 }
    }
}
