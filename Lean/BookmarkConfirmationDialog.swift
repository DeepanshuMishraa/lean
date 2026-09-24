import SwiftUI
import AppKit

struct BookmarkConfirmationDialog: View {
    @ObservedObject var store: LeanStore

    @State private var title: String = ""
    @State private var selectedFolder: String = BookmarkFolder.defaultFolder
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNewFolderFocused: Bool

    private var isAlreadyBookmarked: Bool {
        store.isBookmarked(url: store.dialogBookmarkURL)
    }

    var body: some View {
        VStack(spacing: 14) {
            // Header
            headerView

            // Fields
            VStack(alignment: .leading, spacing: 10) {
                // Name Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(store.bodyFont(size: 11))
                        .foregroundColor(store.adaptiveTheme.secondaryText)

                    TextField("", text: $title)
                        .textFieldStyle(.plain)
                        .font(store.bodyFont(size: 13))
                        .foregroundColor(store.adaptiveTheme.primaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isTitleFocused ? store.adaptiveTheme.primaryText.opacity(0.4) : (store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08)), lineWidth: 1)
                        )
                        .focused($isTitleFocused)
                        .onSubmit {
                            save()
                        }
                }

                // Folder Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder")
                        .font(store.bodyFont(size: 11))
                        .foregroundColor(store.adaptiveTheme.secondaryText)

                    folderPickerView

                    if isCreatingFolder {
                        newFolderInputView
                    }
                }
            }

            // Footer Actions
            footerView
        }
        .padding(16)
        .frame(width: store.scaled(360))
        .background(dialogBackground)
        .overlay(dialogBorder)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(
            color: Color.black.opacity(store.isDarkMode ? 0.45 : 0.14),
            radius: 24,
            x: 0,
            y: 10
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
            save()
            return .handled
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 8) {
            SiteFaviconView(
                url: store.dialogBookmarkURL,
                isDark: store.isDarkMode,
                size: 16
            )
            .frame(width: 18, height: 18)

            Text(isAlreadyBookmarked ? "Bookmark" : "Bookmark Added")
                .font(store.tabTitleFont(size: 13))
                .foregroundColor(store.adaptiveTheme.primaryText)

            Spacer()

            Ph.bookmark.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 13, height: 13)
                .foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.22))
        }
    }

    // MARK: - Folder Picker Dropdown
    private var folderPickerView: some View {
        Menu {
            ForEach(store.bookmarkFolders, id: \.self) { folder in
                Button {
                    selectedFolder = folder
                } label: {
                    HStack {
                        if folder == BookmarkFolder.defaultFolder {
                            Text("★ \(folder)")
                        } else {
                            Text(folder)
                        }
                        if folder == selectedFolder {
                            Spacer()
                            Text("✓")
                        }
                    }
                }
            }

            Divider()

            Button("+ New Folder...") {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                    isCreatingFolder = true
                    newFolderName = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isNewFolderFocused = true
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if selectedFolder == BookmarkFolder.defaultFolder {
                    Ph.star.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)
                        .foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.22))
                } else {
                    Ph.folder.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                }

                Text(selectedFolder)
                    .font(store.bodyFont(size: 12.5))
                    .foregroundColor(store.adaptiveTheme.primaryText)

                Spacer()

                Ph.caretDown.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 8, height: 8)
                    .foregroundColor(store.adaptiveTheme.secondaryText)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Inline New Folder Creator
    private var newFolderInputView: some View {
        HStack(spacing: 6) {
            Ph.folderPlus.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
                .foregroundColor(store.adaptiveTheme.secondaryText)

            TextField("New folder name...", text: $newFolderName)
                .textFieldStyle(.plain)
                .font(store.bodyFont(size: 12))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .focused($isNewFolderFocused)
                .onSubmit {
                    commitNewFolder()
                }

            Button {
                commitNewFolder()
            } label: {
                Text("Create")
                    .font(store.bodyFont(size: 11, weight: .medium))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.1)) {
                    isCreatingFolder = false
                    newFolderName = ""
                    isTitleFocused = true
                }
            } label: {
                Ph.x.bold
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 8, height: 8)
                    .foregroundColor(store.adaptiveTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(store.isDarkMode ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 1)
        )
    }

    private func commitNewFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.addBookmarkFolder(trimmed)
            selectedFolder = trimmed
        }
        withAnimation(.easeOut(duration: 0.1)) {
            isCreatingFolder = false
            newFolderName = ""
            isTitleFocused = true
        }
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Button {
                store.removeBookmarkFromDialog()
            } label: {
                Text("Remove")
                    .font(store.bodyFont(size: 12))
                    .foregroundColor(Color.red.opacity(0.85))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                save()
            } label: {
                Text("Done")
                    .font(store.bodyFont(size: 12, weight: .medium))
                    .foregroundColor(store.isDarkMode ? Color.black : Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(store.isDarkMode ? Color.white : Color.black)
                    )
            }
            .buttonStyle(.plain)
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
                    ? Color(red: 22/255, green: 22/255, blue: 26/255)
                    : Color(white: 0.99)
                ).opacity(0.97)
            )
    }

    private var dialogBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(store.adaptiveTheme.dropdownStroke, lineWidth: 0.75)
    }
}
