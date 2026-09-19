import AppKit
import SwiftUI

struct LeanCommands: Commands {
    @ObservedObject var store: LeanStore

    var body: some Commands {
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

            Button(store.enableWindowBorder ? "Hide Window Frame" : "Show Window Frame") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.enableWindowBorder.toggle()
                }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Divider()
            Button("Zoom In") { store.selectedTab?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { store.selectedTab?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { store.selectedTab?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
        }

        CommandMenu("Tabs") {
            Button("Close Tab") { store.closeSelectedTab() }
                .keyboardShortcut("w", modifiers: .command)
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
    }
}
