import SwiftUI

struct OmnibarView: View {
    @ObservedObject var store: LeanStore
    let isFloating: Bool

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFieldFocused: Bool

    private var openTabsForOmnibar: [(id: UUID, title: String, url: URL)] {
        store.tabs.compactMap { tab in
            guard let url = tab.url, tab.id != store.selectedID else { return nil }
            return (id: tab.id, title: tab.title, url: url)
        }
    }

    private var suggestions: [OmnibarSuggestion] {
        OmnibarService.shared.suggestions(
            for: query,
            history: store.visitedHistory,
            openTabs: openTabsForOmnibar,
            searchEngine: store.searchEngine
        )
    }

    private var showSuggestions: Bool {
        if isFloating {
            return !suggestions.isEmpty
        } else {
            return (store.isNewTabOmnibarFloating || !query.isEmpty) && !suggestions.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            inputHeader

            if showSuggestions {
                suggestionsList
            }
        }
        .frame(width: 580)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isFieldFocused {
                isFieldFocused = true
            }
        }
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: store.isDarkMode ? Color.black.opacity(0.3) : Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        if isFloating {
                            store.floatingPaletteFrame = geo.frame(in: .global)
                        }
                    }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        if isFloating {
                            store.floatingPaletteFrame = newFrame
                        }
                    }
            }
        )
        .background(OmnibarFocusAcquirer())
        .animation(.easeOut(duration: 0.12), value: showSuggestions)
        .onAppear(perform: handleAppear)
        .onChange(of: store.isFloatingOmnibarVisible) { _, isVisible in
            handleFloatingVisibilityChange(isVisible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddress)) { _ in
            requestFieldFocus()
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused && isFloating && store.isFloatingOmnibarVisible {
                DispatchQueue.main.async {
                    if store.isFloatingOmnibarVisible {
                        isFieldFocused = true
                    }
                }
            } else if focused && !isFloating {
                withAnimation(.easeOut(duration: 0.16)) {
                    store.isNewTabOmnibarFloating = true
                }
            }
        }
        .onChange(of: query) { _, newQuery in
            selectedIndex = 0
            if !newQuery.isEmpty && !isFloating {
                withAnimation(.easeOut(duration: 0.16)) {
                    store.isNewTabOmnibarFloating = true
                }
            }
        }
    }

    // MARK: - Input Header
    private var inputHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(store.isDarkMode ? Color.white.opacity(0.4) : Color.black.opacity(0.4))

            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("Search or Enter URL...")
                        .font(store.bodyFont(size: 14))
                        .foregroundColor(store.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
                        .allowsHitTesting(false)
                }

                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .font(store.bodyFont(size: 14))
                    .foregroundColor(store.isDarkMode ? Color.white : Color.black)
                    .focused($isFieldFocused)
                    .onSubmit {
                        submitCurrent()
                    }
                    .onKeyPress(.downArrow) {
                        if !suggestions.isEmpty {
                            selectedIndex = (selectedIndex + 1) % suggestions.count
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        if selectedIndex > 0 {
                            selectedIndex -= 1
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        handleEscape()
                        return .handled
                    }
            }
            .clipped()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isFieldFocused {
                isFieldFocused = true
            }
        }
    }

    // MARK: - Suggestions List
    private var suggestionsList: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(store.isDarkMode ? 0.08 : 0.06)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

            VStack(spacing: 2) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, match in
                    SuggestionRow(
                        match: match,
                        isSelected: index == selectedIndex,
                        store: store,
                        onSelect: { execute(match) },
                        onHover: { selectedIndex = index }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Styling Helpers
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: showSuggestions ? 16 : 12, style: .continuous)
            .fill(store.themeColors.omnibarBackground)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: showSuggestions ? 16 : 12, style: .continuous)
            .stroke(
                store.themeColors.omnibarBorder,
                lineWidth: 1
            )
    }

    // MARK: - Actions
    private func handleAppear() {
        selectedIndex = 0
        if isFloating {
            if store.floatingOmnibarMode == .newTab {
                query = ""
            } else {
                query = store.selectedTab?.url?.absoluteString ?? ""
            }
        }
        requestFieldFocus()
    }

    private func handleFloatingVisibilityChange(_ isVisible: Bool) {
        if isVisible && isFloating {
            selectedIndex = 0
            if store.floatingOmnibarMode == .newTab {
                query = ""
            } else {
                query = store.selectedTab?.url?.absoluteString ?? ""
            }
            requestFieldFocus()
        }
    }

    private func requestFieldFocus() {
        isFieldFocused = true
        DispatchQueue.main.async {
            isFieldFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFieldFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isFieldFocused = true
        }
    }

    private func handleEscape() {
        isFieldFocused = false
        if isFloating {
            store.dismissFloatingOmnibar()
        } else {
            store.dismissNewTabOmnibar()
            query = ""
        }
    }

    private func submitCurrent() {
        if suggestions.indices.contains(selectedIndex) {
            execute(suggestions[selectedIndex])
        } else if let first = suggestions.first {
            execute(first)
        } else {
            submitRaw(query)
        }
    }

    private func execute(_ match: OmnibarSuggestion) {
        isFieldFocused = false

        if match.isSwitchToTab, let tabID = match.tabID {
            store.switchToTab(id: tabID)
        } else {
            if isFloating {
                store.dismissFloatingOmnibar()
            } else {
                store.dismissNewTabOmnibar()
            }

            if store.floatingOmnibarMode == .newTab && store.selectedTab?.url != nil {
                store.newTab(url: match.targetURL)
            } else {
                store.selectedTab?.load(match.targetURL)
            }
        }
    }

    private func submitRaw(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isFieldFocused = false

        if isFloating {
            store.dismissFloatingOmnibar()
        } else {
            store.dismissNewTabOmnibar()
        }

        guard let targetURL = AddressResolver.resolve(trimmed, searchEngine: store.searchEngine) else { return }

        if store.floatingOmnibarMode == .newTab && store.selectedTab?.url != nil {
            store.newTab(url: targetURL)
        } else {
            store.selectedTab?.load(targetURL)
        }
    }
}

// MARK: - Native AppKit Focus Acquirer
private struct OmnibarFocusAcquirer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            focusTextField(near: view)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusTextField(near: view)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            focusTextField(near: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            focusTextField(near: nsView)
        }
    }

    private func focusTextField(near view: NSView) {
        guard let window = view.window else { return }
        var current: NSView? = view
        while let parent = current?.superview {
            if let tf = findTextField(in: parent) {
                if window.firstResponder != tf && !(window.firstResponder is NSTextView && (window.firstResponder as? NSTextView)?.delegate === tf) {
                    window.makeFirstResponder(tf)
                }
                return
            }
            current = parent
        }
        if let tf = findTextField(in: window.contentView) {
            if window.firstResponder != tf && !(window.firstResponder is NSTextView && (window.firstResponder as? NSTextView)?.delegate === tf) {
                window.makeFirstResponder(tf)
            }
        }
    }

    private func findTextField(in view: NSView?) -> NSTextField? {
        guard let view = view else { return nil }
        if let tf = view as? NSTextField, tf.isEditable {
            return tf
        }
        for sub in view.subviews {
            if let found = findTextField(in: sub) {
                return found
            }
        }
        return nil
    }
}
