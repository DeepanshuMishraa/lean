import SwiftUI

struct NewTabToast: Equatable {
    let id = UUID()
    let tabID: LeanTab.ID
    let host: String
}

/// Pill shown top-right after a link opens in a background tab. Tapping it
/// switches to that tab.
struct NewTabToastView: View {
    @ObservedObject var store: LeanStore
    let toast: NewTabToast

    var body: some View {
        Button {
            store.switchToTab(id: toast.tabID)
            store.dismissNewTabToast()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(store.adaptiveTheme.secondaryText)
                Text("Opened in new tab")
                    .font(store.headingFont(size: 12))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                Text(toast.host)
                    .font(store.bodyFont(size: 11))
                    .foregroundColor(store.adaptiveTheme.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 140)
            }
            .padding(.horizontal, 14)
            .frame(height: store.scaled(32))
            .background(
                store.glassActive ? Color.clear : store.adaptiveTheme.dropdownBackground,
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(store.glassActive ? Color.clear : store.adaptiveTheme.dropdownStroke, lineWidth: 0.75)
            )
            .leanGlassIf(store.glassActive, radius: 20)
            .shadow(color: store.glassActive ? .clear : store.adaptiveTheme.dropdownShadow, radius: 10, x: 0, y: 3)
        }
        .buttonStyle(.hitArea)
        .id(toast.id)
    }
}
