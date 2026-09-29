import SwiftUI

/// URL-bar suggestions, published by whichever bar is being edited and drawn
/// by LeanView at the window root. The bars themselves sit inside clipped
/// containers (the tab strip's ScrollView, the sidebar card), which cut off
/// or hide a dropdown drawn as their own overlay.
struct SuggestionDropdown {
    enum Owner { case inlineBar, sidebarBar }

    let owner: Owner
    /// Fixed width, or nil to match the bar it hangs from.
    let width: CGFloat?
    let matches: [OmnibarSuggestion]
    let selectedIndex: Int
    let onSelect: (OmnibarSuggestion) -> Void
}

/// Each bar reports its bounds so LeanView can place its dropdown.
struct SuggestionAnchorKey: PreferenceKey {
    static var defaultValue: [SuggestionDropdown.Owner: Anchor<CGRect>] = [:]

    static func reduce(value: inout [SuggestionDropdown.Owner: Anchor<CGRect>], nextValue: () -> [SuggestionDropdown.Owner: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct SuggestionDropdownView: View {
    @ObservedObject var store: LeanStore
    let model: SuggestionDropdown
    let barWidth: CGFloat

    private func icon(for match: OmnibarSuggestion) -> LeanIcon {
        if match.isSearch { return .magnifyingGlass }
        if match.isSwitchToTab { return .arrowCircleRight }
        return .browser
    }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(model.matches.enumerated()), id: \.element.id) { index, match in
                InlineSuggestionRow(
                    match: match,
                    icon: icon(for: match),
                    isSelected: model.selectedIndex == index,
                    store: store
                ) {
                    model.onSelect(match)
                }
            }
        }
        .padding(4)
        .frame(width: model.width ?? barWidth)
        .background(
            store.glassActive ? Color.clear : store.adaptiveTheme.dropdownBackground,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(store.glassActive ? Color.clear : store.adaptiveTheme.dropdownStroke, lineWidth: 1)
        )
        .leanGlassIf(store.glassActive, radius: 14)
        .shadow(color: store.adaptiveTheme.dropdownShadow, radius: 12, x: 0, y: 4)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { store.inlineSuggestionsFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        store.inlineSuggestionsFrame = newFrame
                    }
            }
        )
        .onDisappear { store.inlineSuggestionsFrame = .zero }
    }
}
