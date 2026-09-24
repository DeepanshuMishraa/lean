import Foundation
import Testing
@testable import Lean

struct BookmarkTests {
    @MainActor
    @Test("BookmarkItem initialization and properties")
    func bookmarkItemModel() {
        let url = URL(string: "https://www.github.com/apple/swift")!
        let item = BookmarkItem(title: "Swift Repo", url: url)

        #expect(item.title == "Swift Repo")
        #expect(item.url == url)
        #expect(item.folder == BookmarkFolder.defaultFolder)
        #expect(item.host == "github.com")

        // Custom folder
        let item2 = BookmarkItem(title: "Docs", url: url, folder: "Work")
        #expect(item2.folder == "Work")

        // Empty folder defaults to Favorites
        let item3 = BookmarkItem(title: "Empty", url: url, folder: "   ")
        #expect(item3.folder == BookmarkFolder.defaultFolder)
    }

    @MainActor
    @Test("BookmarkFolder default and custom names")
    func bookmarkFolderModel() {
        let folder = BookmarkFolder(name: "Reading List")
        #expect(folder.name == "Reading List")
        #expect(folder.id == "Reading List")

        let empty = BookmarkFolder(name: "  ")
        #expect(empty.name == BookmarkFolder.defaultFolder)
    }

    @MainActor
    @Test("LeanStore bookmark addition, query, and deletion")
    func storeBookmarkOperations() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url1 = URL(string: "https://apple.com")!
        let url2 = URL(string: "https://github.com")!

        #expect(store.isBookmarked(url: url1) == false)
        #expect(store.bookmark(for: url1) == nil)

        // Add bookmark
        store.addBookmark(title: "Apple", url: url1, folder: BookmarkFolder.defaultFolder)
        #expect(store.isBookmarked(url: url1) == true)
        #expect(store.bookmark(for: url1)?.title == "Apple")
        #expect(store.bookmarks.count == 1)

        // Add second bookmark to custom folder
        store.addBookmark(title: "GitHub", url: url2, folder: "Dev")
        #expect(store.isBookmarked(url: url2) == true)
        #expect(store.bookmarkFolders.contains("Dev"))
        #expect(store.bookmarks.count == 2)

        // Update bookmark
        if let item = store.bookmark(for: url1) {
            store.updateBookmark(id: item.id, title: "Apple Inc.", url: url1, folder: "Personal")
            #expect(store.bookmark(for: url1)?.title == "Apple Inc.")
            #expect(store.bookmark(for: url1)?.folder == "Personal")
        }

        // Delete bookmark
        if let item = store.bookmark(for: url2) {
            store.deleteBookmark(id: item.id)
            #expect(store.isBookmarked(url: url2) == false)
            #expect(store.bookmarks.count == 1)
        }
    }

    @MainActor
    @Test("LeanStore folder creation, deletion, and bookmark migration")
    func storeBookmarkFolders() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Initial folder contains Favorites
        #expect(store.bookmarkFolders.contains(BookmarkFolder.defaultFolder))

        // Add folder
        store.addBookmarkFolder("Projects")
        #expect(store.bookmarkFolders.contains("Projects"))

        // Add bookmark to Projects
        let url = URL(string: "https://lean.browser")!
        store.addBookmark(title: "Lean", url: url, folder: "Projects")
        #expect(store.bookmark(for: url)?.folder == "Projects")

        // Rename folder
        store.renameBookmarkFolder(from: "Projects", to: "Browser Dev")
        #expect(store.bookmarkFolders.contains("Browser Dev"))
        #expect(!store.bookmarkFolders.contains("Projects"))
        #expect(store.bookmark(for: url)?.folder == "Browser Dev")

        // Deleting folder moves bookmarks to default folder
        store.deleteBookmarkFolder("Browser Dev")
        #expect(!store.bookmarkFolders.contains("Browser Dev"))
        #expect(store.bookmark(for: url)?.folder == BookmarkFolder.defaultFolder)

        // Cannot delete default folder
        store.deleteBookmarkFolder(BookmarkFolder.defaultFolder)
        #expect(store.bookmarkFolders.contains(BookmarkFolder.defaultFolder))
    }

    @MainActor
    @Test("LeanStore bookmark confirmation dialog flow")
    func storeBookmarkConfirmationDialog() throws {
        let (store, directory) = try makeIsolatedTestStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = URL(string: "https://news.ycombinator.com")!
        store.newTab(url: url)

        #expect(store.isBookmarked(url: url) == false)
        #expect(store.isBookmarkDialogPresented == false)

        // Trigger Cmd+D / toggleBookmarkCurrentTab -> opens dialog and bookmarks tab
        store.toggleBookmarkCurrentTab()
        #expect(store.isBookmarked(url: url) == true)
        #expect(store.isBookmarkDialogPresented == true)
        #expect(store.dialogBookmarkURL == url)
        #expect(store.bookmark(for: url)?.folder == BookmarkFolder.defaultFolder)

        // Save dialog with new name and folder
        store.addBookmarkFolder("Tech")
        store.saveBookmarkDialog(title: "Hacker News", folder: "Tech")
        #expect(store.isBookmarkDialogPresented == false)
        #expect(store.bookmark(for: url)?.title == "Hacker News")
        #expect(store.bookmark(for: url)?.folder == "Tech")

        // Trigger again to re-open dialog for existing bookmark
        store.toggleBookmarkCurrentTab()
        #expect(store.isBookmarkDialogPresented == true)
        #expect(store.dialogBookmarkTitle == "Hacker News")
        #expect(store.dialogBookmarkFolder == "Tech")

        // Remove bookmark from dialog
        store.removeBookmarkFromDialog()
        #expect(store.isBookmarked(url: url) == false)
        #expect(store.isBookmarkDialogPresented == false)
    }

    @MainActor
    @Test("CustomShortcuts supports bookmarks actions")
    func shortcutActions() {
        let toggleAction = ShortcutAction.toggleBookmarks
        #expect(toggleAction.title == "Show Bookmarks")
        #expect(toggleAction.group == .bookmarks)
        #expect(toggleAction.defaultShortcut.key == "b")
        #expect(toggleAction.defaultShortcut.modifiers.contains("command"))
        #expect(toggleAction.defaultShortcut.modifiers.contains("option"))

        let bookmarkAction = ShortcutAction.bookmarkCurrentTab
        #expect(bookmarkAction.title == "Bookmark Current Tab")
        #expect(bookmarkAction.group == .bookmarks)
        #expect(bookmarkAction.defaultShortcut.key == "d")
        #expect(bookmarkAction.defaultShortcut.modifiers.contains("command"))
    }
}
