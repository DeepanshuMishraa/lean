import AppKit
import SwiftUI

struct LeanCommands: Commands {
    @ObservedObject var store: LeanStore
    @ObservedObject var updater: AppUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)

            Button("Welcome & Onboarding Tour...") {
                store.startOnboarding()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                store.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") {
                store.closeSelectedTab()
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print...") {
                store.selectedTab?.printPage()
            }
            .disabled(store.selectedTab.map { $0.isSettingsPage || ($0.url == nil && !$0.isPageSource) || $0.webView.window == nil } ?? true)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Tab") { store.handleNewTabCommand() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Reopen Closed Tab") { store.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Button("Find on Page") {
                NotificationCenter.default.post(name: .showFind, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Focus Address Bar") {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    store.isInlineURLEditing = true
                }
                NotificationCenter.default.post(name: .focusAddress, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)
        }

        CommandMenu("View") {
            Button(store.isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode") {
                store.toggleTheme()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button(store.enableZenMode ? "Exit Zen Mode" : "Enter Zen Mode") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.enableZenMode.toggle()
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])

            if store.tabLayout == .sidebar {
                Button(store.isSidebarCollapsed ? "Pin Sidebar (Always Expanded)" : "Auto-Hide Sidebar") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.toggleSidebar()
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
            } else {
                Button(store.enableWindowBorder ? "Hide Window Frame" : "Show Window Frame") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.enableWindowBorder.toggle()
                    }
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }

            Divider()
            Button("Zoom In") { store.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { store.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { store.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
        }

        CommandMenu("Tabs") {
            Button(store.selectedTab?.isPinned == true ? "Unpin Tab" : "Pin Tab") {
                if let tab = store.selectedTab, tab.url != nil {
                    store.togglePin(tab: tab)
                }
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(store.selectedTab?.url == nil)

            Button("Close Tab") { store.closeSelectedTab() }
                .keyboardShortcut("w", modifiers: .command)

            if let selectedTab = store.selectedTab, selectedTab.isSplit {
                Button("Separate Split Tabs") {
                    store.separateSplitTabs(selectedTab)
                }
                .keyboardShortcut("s", modifiers: [.command, .option, .shift])
            } else {
                Button("Open as Split") {
                    if let selected = store.selectedTab {
                        store.openTabAsSplit(selected)
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(store.selectedTab == nil)
            }

            Button("Next Tab") { store.selectNextTab() }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Tab") { store.selectNextTab(reverse: true) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            ForEach(1...9, id: \.self) { number in
                Button(number == 9 ? "Last Tab" : "Tab \(number)") {
                    store.selectTab(number: number)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
        }

        CommandMenu("Navigation") {
            Button("Back") { store.selectedTab?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward") { store.selectedTab?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Button("Reload") { store.selectedTab?.reload() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Stop") { store.selectedTab?.stop() }
                .keyboardShortcut(.escape, modifiers: [])
        }

        CommandGroup(replacing: .help) {
            Button("Welcome & Onboarding Tour...") {
                store.startOnboarding()
            }
        }
    }
}
