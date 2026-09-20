import AppKit
import SwiftUI

// MARK: - Shortcut Action Identifier
public enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    // Tabs
    case newTab = "newTab"
    case closeTab = "closeTab"
    case reopenTab = "reopenTab"
    case nextTab = "nextTab"
    case previousTab = "previousTab"
    case goToLastTab = "goToLastTab"

    // Navigation
    case goBack = "goBack"
    case goForward = "goForward"
    case reload = "reload"
    case hardReload = "hardReload"
    case stopLoading = "stopLoading"

    // Omnibar & Search
    case focusAddress = "focusAddress"
    case findOnPage = "findOnPage"
    case dismiss = "dismiss"

    // View
    case toggleTheme = "toggleTheme"
    case toggleZen = "toggleZen"
    case toggleFrame = "toggleFrame"
    case zoomIn = "zoomIn"
    case zoomOut = "zoomOut"
    case actualSize = "actualSize"
    case openSettings = "openSettings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newTab: return "New Tab"
        case .closeTab: return "Close Tab"
        case .reopenTab: return "Reopen Closed Tab"
        case .nextTab: return "Next Tab"
        case .previousTab: return "Previous Tab"
        case .goToLastTab: return "Go to Last Tab"
        case .goBack: return "Back"
        case .goForward: return "Forward"
        case .reload: return "Reload Page"
        case .hardReload: return "Hard Reload"
        case .stopLoading: return "Stop Loading"
        case .focusAddress: return "Focus Address Bar"
        case .findOnPage: return "Find on Page"
        case .dismiss: return "Dismiss / Unfocus"
        case .toggleTheme: return "Toggle Light/Dark"
        case .toggleZen: return "Toggle Zen Mode"
        case .toggleFrame: return "Toggle Window Frame"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .actualSize: return "Actual Size"
        case .openSettings: return "Preferences"
        }
    }

    public var description: String {
        switch self {
        case .newTab: return "Open a fresh tab or Omnibar"
        case .closeTab: return "Close the currently active tab"
        case .reopenTab: return "Restore the most recently closed tab"
        case .nextTab: return "Cycle forward through open tabs"
        case .previousTab: return "Cycle backward through open tabs"
        case .goToLastTab: return "Jump directly to the last tab"
        case .goBack: return "Navigate to previous page in session history"
        case .goForward: return "Navigate forward in session history"
        case .reload: return "Reload the current page"
        case .hardReload: return "Bypass cache and reload page"
        case .stopLoading: return "Halt loading current web document"
        case .focusAddress: return "Activate inline address field or Omnibar"
        case .findOnPage: return "Reveal interactive in-page text search bar"
        case .dismiss: return "Close dropdowns, Omnibar, or inline editing"
        case .toggleTheme: return "Switch between light and dark theme mode"
        case .toggleZen: return "Hide interface elements for pure immersion"
        case .toggleFrame: return "Show or hide subtle framed border"
        case .zoomIn: return "Enlarge web page contents"
        case .zoomOut: return "Reduce web page contents"
        case .actualSize: return "Reset page zoom to 100%"
        case .openSettings: return "Open Lean Browser settings window"
        }
    }

    public enum Group: String, CaseIterable, Identifiable {
        case all = "All"
        case tabs = "Tabs"
        case navigation = "Navigation"
        case omnibar = "Address & Search"
        case view = "View"

        public var id: String { rawValue }
    }

    public var group: Group {
        switch self {
        case .newTab, .closeTab, .reopenTab, .nextTab, .previousTab, .goToLastTab:
            return .tabs
        case .goBack, .goForward, .reload, .hardReload, .stopLoading:
            return .navigation
        case .focusAddress, .findOnPage, .dismiss:
            return .omnibar
        case .toggleTheme, .toggleZen, .toggleFrame, .zoomIn, .zoomOut, .actualSize, .openSettings:
            return .view
        }
    }

    public var defaultShortcut: CustomKeyCombo {
        switch self {
        case .newTab: return CustomKeyCombo(key: "t", modifiers: ["command"])
        case .closeTab: return CustomKeyCombo(key: "w", modifiers: ["command"])
        case .reopenTab: return CustomKeyCombo(key: "t", modifiers: ["shift", "command"])
        case .nextTab: return CustomKeyCombo(key: "tab", modifiers: ["control"])
        case .previousTab: return CustomKeyCombo(key: "tab", modifiers: ["control", "shift"])
        case .goToLastTab: return CustomKeyCombo(key: "9", modifiers: ["command"])
        case .goBack: return CustomKeyCombo(key: "[", modifiers: ["command"])
        case .goForward: return CustomKeyCombo(key: "]", modifiers: ["command"])
        case .reload: return CustomKeyCombo(key: "r", modifiers: ["command"])
        case .hardReload: return CustomKeyCombo(key: "r", modifiers: ["shift", "command"])
        case .stopLoading: return CustomKeyCombo(key: "escape", modifiers: [])
        case .focusAddress: return CustomKeyCombo(key: "l", modifiers: ["command"])
        case .findOnPage: return CustomKeyCombo(key: "f", modifiers: ["command"])
        case .dismiss: return CustomKeyCombo(key: "escape", modifiers: [])
        case .toggleTheme: return CustomKeyCombo(key: "d", modifiers: ["shift", "command"])
        case .toggleZen: return CustomKeyCombo(key: "z", modifiers: ["shift", "command"])
        case .toggleFrame: return CustomKeyCombo(key: "b", modifiers: ["shift", "command"])
        case .zoomIn: return CustomKeyCombo(key: "+", modifiers: ["command"])
        case .zoomOut: return CustomKeyCombo(key: "-", modifiers: ["command"])
        case .actualSize: return CustomKeyCombo(key: "0", modifiers: ["command"])
        case .openSettings: return CustomKeyCombo(key: ",", modifiers: ["command"])
        }
    }

    @MainActor
    public func performAction(in store: LeanStore) {
        switch self {
        case .newTab:
            store.handleNewTabCommand()
        case .closeTab:
            store.closeSelectedTab()
        case .reopenTab:
            store.reopenClosedTab()
        case .nextTab:
            store.selectNextTab()
        case .previousTab:
            store.selectNextTab(reverse: true)
        case .goToLastTab:
            store.selectTab(number: 9)
        case .goBack:
            store.selectedTab?.goBack()
        case .goForward:
            store.selectedTab?.goForward()
        case .reload:
            store.selectedTab?.reload()
        case .hardReload:
            store.selectedTab?.reloadFromOrigin()
        case .stopLoading:
            store.selectedTab?.stop()
        case .focusAddress:
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                store.isInlineURLEditing = true
            }
            NotificationCenter.default.post(name: .focusAddress, object: nil)
        case .findOnPage:
            NotificationCenter.default.post(name: .showFind, object: nil)
        case .dismiss:
            store.dismissInlineURLEditing()
            store.dismissFloatingOmnibar()
            withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                store.isQuickSettingsPresented = false
            }
        case .toggleTheme:
            store.toggleTheme()
        case .toggleZen:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                store.enableZenMode.toggle()
            }
        case .toggleFrame:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                store.enableWindowBorder.toggle()
            }
        case .zoomIn:
            store.selectedTab?.zoomIn()
        case .zoomOut:
            store.selectedTab?.zoomOut()
        case .actualSize:
            store.selectedTab?.resetZoom()
        case .openSettings:
            store.openSettings()
        }
    }
}

// MARK: - Key Combo Representation
public struct CustomKeyCombo: Codable, Equatable {
    public var key: String // "t", "w", "tab", "escape", etc.
    public var modifiers: [String] // "command", "shift", "option", "control"

    public init(key: String, modifiers: [String] = []) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    public var displayKeys: [String] {
        var keys: [String] = []
        if modifiers.contains("control") { keys.append("⌃") }
        if modifiers.contains("option") { keys.append("⌥") }
        if modifiers.contains("shift") { keys.append("⇧") }
        if modifiers.contains("command") { keys.append("⌘") }

        switch key {
        case "escape": keys.append("Esc")
        case "tab": keys.append("Tab")
        case "return": keys.append("↩")
        case "space": keys.append("Space")
        case "left": keys.append("←")
        case "right": keys.append("→")
        case "up": keys.append("↑")
        case "down": keys.append("↓")
        default: keys.append(key.uppercased())
        }
        return keys
    }

    public func matches(event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let expectedCommand = modifiers.contains("command")
        let expectedShift = modifiers.contains("shift")
        let expectedOption = modifiers.contains("option")
        let expectedControl = modifiers.contains("control")

        guard flags.contains(.command) == expectedCommand,
              flags.contains(.shift) == expectedShift,
              flags.contains(.option) == expectedOption,
              flags.contains(.control) == expectedControl else {
            return false
        }

        switch key {
        case "escape": return event.keyCode == 53
        case "tab": return event.keyCode == 48
        case "return": return event.keyCode == 36
        case "space": return event.keyCode == 49
        case "+":
            if let chars = event.charactersIgnoringModifiers {
                return chars == "+" || chars == "="
            }
            return false
        case "-":
            if let chars = event.charactersIgnoringModifiers {
                return chars == "-" || chars == "_"
            }
            return false
        default:
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                return chars == key
            }
            return false
        }
    }

    public static func from(event: NSEvent) -> CustomKeyCombo? {
        let keyCode = event.keyCode
        // Ignore modifier-only key presses
        if [54, 55, 56, 57, 58, 59, 60, 61, 62].contains(keyCode) {
            return nil
        }

        var mods: [String] = []
        if event.modifierFlags.contains(.control) { mods.append("control") }
        if event.modifierFlags.contains(.option) { mods.append("option") }
        if event.modifierFlags.contains(.shift) { mods.append("shift") }
        if event.modifierFlags.contains(.command) { mods.append("command") }

        let key: String
        switch keyCode {
        case 53: key = "escape"
        case 48: key = "tab"
        case 36: key = "return"
        case 49: key = "space"
        case 123: key = "left"
        case 124: key = "right"
        case 125: key = "down"
        case 126: key = "up"
        default:
            guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
                return nil
            }
            if chars == "+" || chars == "=" {
                key = "+"
            } else if chars == "-" || chars == "_" {
                key = "-"
            } else {
                key = chars
            }
        }

        // Require at least one modifier key or a navigation/special key
        if mods.isEmpty && !["escape", "tab", "return", "space"].contains(key) {
            return nil
        }

        return CustomKeyCombo(key: key, modifiers: mods)
    }
}
