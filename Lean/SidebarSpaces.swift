import AppKit
import SwiftUI

/// Which way the sidebar slides when the space changes.
enum SpaceDirection {
    case forward
    case backward
}

// MARK: - Space header

/// The name of the space in front. A click opens its theme; the right-click
/// menu renames or deletes it.
struct SidebarSpaceHeader: View {
    @ObservedObject var store: LeanStore
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private var space: Space { store.currentSpace }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(space.theme.colors.first ?? store.adaptiveTheme.secondaryText.opacity(0.6))
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(store.adaptiveTheme.primaryText.opacity(0.15), lineWidth: 0.5))

            if isRenaming {
                TextField("Space name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(store.headingFont(size: 13.5, weight: .semibold))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                    .focused($isNameFocused)
                    .onSubmit(commitRename)
                    .onKeyPress(.escape) {
                        isRenaming = false
                        return .handled
                    }
                    .onChange(of: isNameFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Text(space.name)
                    .font(store.headingFont(size: 13.5, weight: .semibold))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovered && !isRenaming {
                LeanIcon.palette.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundColor(store.adaptiveTheme.secondaryText)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: store.scaled(34))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered || store.isSpaceThemeEditorPresented
                      ? (store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                      : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming else { return }
            Haptics.select()
            withAnimation(.easeOut(duration: 0.14)) { store.isSpaceThemeEditorPresented.toggle() }
        }
        .onTapGesture(count: 2) { startRename() }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .help("Click to change this space's look. Double-click to rename.")
        .contextMenu { SpaceMenu(store: store, space: space, onRename: startRename) }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { store.spaceThemeButtonFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in store.spaceThemeButtonFrame = frame }
            }
        )
    }

    private func startRename() {
        draftName = space.name
        isRenaming = true
        isNameFocused = true
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        store.renameSpace(id: space.id, to: draftName)
    }
}

/// Rename, theme and delete, for the header and for each dot.
private struct SpaceMenu: View {
    @ObservedObject var store: LeanStore
    let space: Space
    let onRename: () -> Void

    var body: some View {
        Button("Rename…") {
            if space.id != store.selectedSpaceID { store.switchToSpace(id: space.id) }
            onRename()
        }
        Button("Edit Theme…") {
            if space.id != store.selectedSpaceID { store.switchToSpace(id: space.id) }
            store.isSpaceThemeEditorPresented = true
        }
        Divider()
        Button("Delete Space", role: .destructive) {
            confirmDelete()
        }
        .disabled(store.spaces.count < 2)
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete “\(space.name)”?"
        alert.informativeText = "Its tabs close, and its cookies, site logins, history, bookmarks and download list are erased from this Mac. Downloaded files stay where they are. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete Space")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            store.deleteSpace(id: space.id)
        }
    }
}

// MARK: - Clear and New Tab rows

/// A hairline with "Clear" at its end: closes the space's tabs that aren't pinned.
struct SidebarClearRow: View {
    @ObservedObject var store: LeanStore
    @State private var isHovered = false

    var body: some View {
        if !store.unpinnedTabs.isEmpty {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(store.themeColors.divider)
                    .frame(height: 0.75)
                Button {
                    Haptics.select()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        store.closeUnpinnedTabs()
                    }
                } label: {
                    Text("Clear")
                        .font(store.bodyFont(size: 11.5))
                        .foregroundColor(isHovered ? store.adaptiveTheme.primaryText : store.adaptiveTheme.secondaryText)
                        .padding(.horizontal, 4)
                        .frame(height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hitArea)
                .onHover { isHovered = $0 }
                .help("Close every tab in this space that isn't pinned")
            }
        }
    }
}

struct SidebarNewTabRow: View {
    @ObservedObject var store: LeanStore
    @State private var isHovered = false

    var body: some View {
        Button {
            _ = store.newTab()
        } label: {
            HStack(spacing: 10) {
                LeanIcon.plus.bold
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                    .frame(width: 16)
                Text("New Tab")
                    .font(store.bodyFont(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundColor(isHovered ? store.adaptiveTheme.primaryText : store.adaptiveTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: store.scaled(34))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? (store.isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.05)) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.hitArea)
        .onHover { isHovered = $0 }
        .help("New Tab (⌘T)")
    }
}

// MARK: - Space dots

/// One dot per space; the one in front is larger and wears its colour.
struct SpaceDots: View {
    @ObservedObject var store: LeanStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(store.spaces) { space in
                SpaceDot(store: store, space: space, isSelected: space.id == store.selectedSpaceID)
            }
        }
    }
}

private struct SpaceDot: View {
    @ObservedObject var store: LeanStore
    let space: Space
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            guard !isSelected else { return }
            Haptics.select()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                store.switchToSpace(id: space.id)
            }
        } label: {
            Circle()
                .fill(fill)
                .frame(width: isSelected ? 8 : 6, height: isSelected ? 8 : 6)
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.hitArea)
        .onHover { isHovered = $0 }
        .help(space.name)
        .contextMenu { SpaceMenu(store: store, space: space, onRename: {}) }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }

    private var fill: Color {
        if isSelected { return space.theme.colors.first ?? store.adaptiveTheme.primaryText }
        return store.adaptiveTheme.secondaryText.opacity(isHovered ? 0.8 : 0.4)
    }
}

// MARK: - Swipe

/// A two-finger sideways swipe over the sidebar moves to the next or the
/// previous space, one space per swipe, with a tick on the trackpad.
struct SpaceSwipe: ViewModifier {
    @ObservedObject var store: LeanStore
    @State private var isHovering = false
    @State private var monitor: Any?
    @State private var travel: CGFloat = 0
    @State private var hasSwitched = false

    /// Points of sideways travel that make a swipe.
    private static let threshold: CGFloat = 70

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .onAppear(perform: install)
            .onDisappear(perform: uninstall)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handle(event)
            return event
        }
    }

    private func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        // Trackpad gestures only, and never their momentum: one swipe, one space.
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty, store.spaces.count > 1 else { return }
        if event.phase.contains(.began) {
            travel = 0
            hasSwitched = false
        }
        guard isHovering, !hasSwitched else { return }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5 else { return }
        // The way the fingers moved, whatever the scroll direction setting.
        travel += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        guard abs(travel) >= Self.threshold else { return }
        hasSwitched = true
        let forward = travel < 0
        Haptics.select()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            store.switchToAdjacentSpace(forward: forward)
        }
    }
}
