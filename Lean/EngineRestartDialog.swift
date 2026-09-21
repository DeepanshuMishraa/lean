import PhosphorSwift
import SwiftUI

/// Restart-to-switch-engines dialog. Same card language as the popovers
/// (blur, hairline stroke, double shadow), centered and modal.
struct EngineRestartDialog: View {
    @ObservedObject var store: LeanStore

    @State private var isRestartHovered = false
    @State private var isLaterHovered = false

    private var pendingKind: BrowserEngineKind {
        store.engineKind
    }

    private var restartRed: Color {
        store.isDarkMode
            ? Color(red: 0.92, green: 0.28, blue: 0.30)
            : Color(red: 0.80, green: 0.20, blue: 0.20)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(store.adaptiveTheme.dropdownStroke, lineWidth: 0.5)
                    )
                    .frame(width: 44, height: 44)
                Ph.arrowsCounterClockwise.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundColor(store.adaptiveTheme.primaryText)
            }
            .padding(.bottom, 12)

            Text("Switch to \(pendingKind.title)?")
                .font(store.headingFont(size: 14.5))
                .foregroundColor(store.adaptiveTheme.primaryText)

            Text("Lean needs a quick restart to change engines. Your open tabs will be restored.")
                .font(store.bodyFont(size: 12.5))
                .foregroundColor(store.adaptiveTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 6)

            HStack(spacing: 8) {
                Button {
                    store.cancelEngineChange()
                } label: {
                    Text("Not now")
                        .font(store.bodyFont(size: 12.5))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            isLaterHovered
                                ? (store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isLaterHovered = $0 }

                Button {
                    store.restartForEngineChange()
                } label: {
                    Text("Restart now")
                        .font(store.leanUIFont.font(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            restartRed.opacity(isRestartHovered ? 0.85 : 1.0),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isRestartHovered = $0 }
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 340)
        .background(
            (store.isDarkMode
                ? Color(red: 18/255, green: 18/255, blue: 21/255)
                : Color(white: 0.995)
            ).opacity(0.98)
        )
        .background(
            VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(store.adaptiveTheme.dropdownStroke, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(store.isDarkMode ? 0.5 : 0.16), radius: 28, x: 0, y: 12)
        .shadow(color: Color.black.opacity(store.isDarkMode ? 0.25 : 0.05), radius: 3, x: 0, y: 1)
    }
}
