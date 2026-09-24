import SwiftUI
import AppKit

struct BookmarkConfirmationDialog: View {
    @ObservedObject var store: LeanStore

    @State private var title: String = ""
    @State private var selectedFolder: String = BookmarkFolder.defaultFolder
    @State private var isFolderDropdownOpen: Bool = false
    @State private var isCreatingFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var isRemoveHovered: Bool = false
    @State private var isDoneHovered: Bool = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNewFolderFocused: Bool

    private var isAlreadyBookmarked: Bool {
        store.isBookmarked(url: store.dialogBookmarkURL)
    }

    private var hostDisplay: String {
        guard let url = store.dialogBookmarkURL, let host = url.host?.lowercased() else { return "" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerView

            // Fields
            VStack(alignment: .leading, spacing: 12) {
                // Name Field
                VStack(alignment: .leading, spacing: 5) {
                    Text("NAME")
                        .font(store.bodyFont(size: 10, weight: .medium))
                        .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.85))
                        .tracking(0.5)

                    HStack(spacing: 8) {
                        TextField("", text: $title)
                            .textFieldStyle(.plain)
                            .font(store.bodyFont(size: 13))
                            .foregroundColor(store.adaptiveTheme.primaryText)
                            .focused($isTitleFocused)
                            .onSubmit {
                                save()
                            }
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                isTitleFocused
                                    ? (store.isDarkMode ? Color.white.opacity(0.28) : Color.black.opacity(0.22))
                                    : (store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06)),
                                lineWidth: 1
                            )
                    )
                }

                // Folder Field
                VStack(alignment: .leading, spacing: 5) {
                    Text("FOLDER")
                        .font(store.bodyFont(size: 10, weight: .medium))
                        .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.85))
                        .tracking(0.5)

                    if isCreatingFolder {
                        newFolderInputView
                    } else {
                        folderTriggerButton

                        if isFolderDropdownOpen {
                            folderDropdownCard
                                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                        }
                    }
                }
            }

            // Footer Actions
            footerView
        }
        .padding(16)
        .frame(width: store.scaled(370))
        .background(dialogBackground)
        .overlay(dialogBorder)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(
            color: Color.black.opacity(store.isDarkMode ? 0.45 : 0.12),
            radius: 28,
            x: 0,
            y: 12
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        store.dialogBookmarkFrame = geo.frame(in: .global)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        store.dialogBookmarkFrame = newFrame
                    }
            }
        )
        .onAppear {
            title = store.dialogBookmarkTitle
            selectedFolder = store.dialogBookmarkFolder
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTitleFocused = true
            }
        }
        .onChange(of: title) { _, newTitle in
            store.dialogBookmarkTitle = newTitle
        }
        .onChange(of: selectedFolder) { _, newFolder in
            store.dialogBookmarkFolder = newFolder
        }
        .onKeyPress(.escape) {
            if isFolderDropdownOpen {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.82)) {
                    isFolderDropdownOpen = false
                }
                return .handled
            }
            if isCreatingFolder {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.82)) {
                    isCreatingFolder = false
                    isTitleFocused = true
                }
                return .handled
            }
            save()
            return .handled
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                    .frame(width: 28, height: 28)

                SiteFaviconView(
                    url: store.dialogBookmarkURL,
                    isDark: store.isDarkMode,
                    size: 16
                )
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(isAlreadyBookmarked ? "Edit Bookmark" : "Saved to Bookmarks")
                    .font(store.headingFont(size: 13, weight: .semibold))
                    .foregroundColor(store.adaptiveTheme.primaryText)

                if !hostDisplay.isEmpty {
                    Text(hostDisplay)
                        .font(store.bodyFont(size: 11))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            LeanIcon.star.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.22))
        }
    }

    // MARK: - Folder Trigger Button
    private var folderTriggerButton: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                isFolderDropdownOpen.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                if selectedFolder == BookmarkFolder.defaultFolder {
                    LeanIcon.star.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.22))
                } else {
                    LeanIcon.folder.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                }

                Text(selectedFolder)
                    .font(store.bodyFont(size: 13, weight: .medium))
                    .foregroundColor(store.adaptiveTheme.primaryText)

                Spacer()

                LeanIcon.caretDown.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 9, height: 9)
                    .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.7))
                    .rotationEffect(.degrees(isFolderDropdownOpen ? 180 : 0))
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isFolderDropdownOpen
                            ? (store.isDarkMode ? Color.white.opacity(0.24) : Color.black.opacity(0.18))
                            : (store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bespoke Folder Dropdown Card
    private var folderDropdownCard: some View {
        VStack(spacing: 2) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1.5) {
                    ForEach(store.bookmarkFolders, id: \.self) { folder in
                        folderOptionRow(folder: folder)
                    }
                }
            }
            .frame(maxHeight: 125)

            Divider()
                .padding(.vertical, 3)
                .opacity(store.isDarkMode ? 0.12 : 0.08)

            Button {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                    isFolderDropdownOpen = false
                    isCreatingFolder = true
                    newFolderName = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isNewFolderFocused = true
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    LeanIcon.folderPlus.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .foregroundColor(store.adaptiveTheme.primaryText)

                    Text("New Folder...")
                        .font(store.bodyFont(size: 12, weight: .medium))
                        .foregroundColor(store.adaptiveTheme.primaryText)

                    Spacer()
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                        .fill(Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(DropdownRowButtonStyle(isDark: store.isDarkMode))
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(store.isDarkMode ? Color(red: 26/255, green: 26/255, blue: 30/255) : Color(white: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(store.isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.09), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(store.isDarkMode ? 0.35 : 0.08), radius: 10, x: 0, y: 4)
    }

    private func folderOptionRow(folder: String) -> some View {
        let isSelected = folder == selectedFolder
        return Button {
            selectedFolder = folder
            withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                isFolderDropdownOpen = false
            }
        } label: {
            HStack(spacing: 8) {
                if folder == BookmarkFolder.defaultFolder {
                    LeanIcon.star.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.22))
                } else {
                    LeanIcon.folder.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                }

                Text(folder)
                    .font(store.bodyFont(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundColor(store.adaptiveTheme.primaryText)

                Spacer()

                if isSelected {
                    LeanIcon.check.bold
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)
                        .foregroundColor(store.adaptiveTheme.primaryText)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(isSelected ? (store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05)) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DropdownRowButtonStyle(isDark: store.isDarkMode))
    }

    // MARK: - Inline New Folder Creator
    private var newFolderInputView: some View {
        HStack(spacing: 7) {
            LeanIcon.folderPlus.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 13, height: 13)
                .foregroundColor(store.adaptiveTheme.secondaryText)

            TextField("New folder name...", text: $newFolderName)
                .textFieldStyle(.plain)
                .font(store.bodyFont(size: 12.5))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .focused($isNewFolderFocused)
                .onSubmit {
                    commitNewFolder()
                }

            Button {
                commitNewFolder()
            } label: {
                Text("Create")
                    .font(store.bodyFont(size: 11, weight: .semibold))
                    .foregroundColor(store.isDarkMode ? Color.black : Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(store.isDarkMode ? Color.white : Color.black)
                    )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                    isCreatingFolder = false
                    newFolderName = ""
                    isTitleFocused = true
                }
            } label: {
                LeanIcon.x.bold
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 10, height: 10)
                    .foregroundColor(store.adaptiveTheme.secondaryText)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(store.isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(store.isDarkMode ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 1)
        )
    }

    private func commitNewFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.addBookmarkFolder(trimmed)
            selectedFolder = trimmed
        }
        withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
            isCreatingFolder = false
            newFolderName = ""
            isTitleFocused = true
        }
    }

    // MARK: - Footer Actions
    private var footerView: some View {
        HStack {
            Button {
                store.removeBookmarkFromDialog()
            } label: {
                HStack(spacing: 6) {
                    LeanIcon.trash.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)

                    Text("Remove")
                        .font(store.bodyFont(size: 12, weight: .medium))
                }
                .foregroundColor(isRemoveHovered ? Color.red : Color.red.opacity(0.85))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isRemoveHovered ? Color.red.opacity(0.12) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isRemoveHovered = $0 }
            .help("Delete this bookmark")

            Spacer()

            Button {
                save()
            } label: {
                Text("Done")
                    .font(store.bodyFont(size: 12.5, weight: .semibold))
                    .foregroundColor(store.isDarkMode ? Color.black : Color.white)
                    .padding(.horizontal, 18)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(store.isDarkMode ? (isDoneHovered ? Color.white.opacity(0.9) : Color.white) : (isDoneHovered ? Color.black.opacity(0.85) : Color.black))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isDoneHovered = $0 }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 4)
    }

    private func save() {
        store.saveBookmarkDialog(title: title, folder: selectedFolder)
    }

    // MARK: - Styling
    private var dialogBackground: some View {
        VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
            .background(
                (store.isDarkMode
                    ? Color(red: 20/255, green: 20/255, blue: 24/255)
                    : Color(white: 0.99)
                ).opacity(0.98)
            )
    }

    private var dialogBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(store.adaptiveTheme.dropdownStroke, lineWidth: 0.75)
    }
}

// MARK: - Hover button style for dropdown rows
private struct DropdownRowButtonStyle: ButtonStyle {
    let isDark: Bool

    func makeBody(configuration: Configuration) -> some View {
        DropdownRowButtonContainer(isDark: isDark, configuration: configuration)
    }

    private struct DropdownRowButtonContainer: View {
        let isDark: Bool
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                        .fill(isHovered ? (isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.05)) : Color.clear)
                )
                .onHover { isHovered = $0 }
        }
    }
}
