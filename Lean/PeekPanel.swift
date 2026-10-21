//
//  PeekPanel.swift
//  Lean
//
//  A link preview panel for force- and shift-click peeking. It grows out of
//  the link that was pressed, and leaves either back into it (closed) or by
//  filling the page card (kept as a tab). Floating actions beside it:
//  - Close preview
//  - Expand as new tab
//  Split view has no button, only its shortcut (⌘⌥⏎).
//

import AppKit
import SwiftUI

/// How a peek leaves: back into its link, or out to fill the page card as a tab.
enum PeekExit: Equatable {
    case close
    case keep

    /// A curve that lands on time: the store finishes the exit when it ends.
    static let duration: TimeInterval = 0.32
    static let animation = Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: duration)
}

/// The link preview panel floating over the page with a backdrop behind it.
struct PeekPanel: View {
    @ObservedObject var store: LeanStore
    /// Plain ref on purpose: only the tiny `PeekProgressBar` subview
    /// observes the tab, so progress ticks (10Hz) don't re-evaluate this
    /// whole card + its hosted WebView.
    let tab: LeanTab
    /// The page card in global coordinates: where a kept peek grows to.
    let pageCard: CGRect?

    /// Off until the panel's first frame, so it can grow from its link.
    @State private var isShown = false

    private enum Pose {
        /// Shrunk into the link it came from.
        case seed
        case resting
        /// Over the page card, about to become its tab.
        case filled
    }

    private var pose: Pose {
        switch store.peekExit {
        case .keep: return .filled
        case .close: return .seed
        case nil: return isShown ? .resting : .seed
        }
    }

    private var glass: Bool { store.glassActive }

    private var cardBackground: Color {
        store.isDarkMode ? Color(red: 20/255, green: 20/255, blue: 23/255) : Color(white: 0.99)
    }

    var body: some View {
        GeometryReader { geo in
            let space = geo.frame(in: .global)
            // Everything happens over the page card: the sidebar stays as it is.
            let page = pageCard.map { $0.offsetBy(dx: -space.minX, dy: -space.minY) }
                ?? CGRect(origin: .zero, size: geo.size)
            let resting = Self.restingRect(in: page)
            let rect: CGRect = switch pose {
            case .seed: seedRect(from: resting, space: space)
            case .resting: resting
            case .filled: page
            }
            let isResting = pose == .resting

            ZStack(alignment: .topLeading) {
                // A click anywhere beside the card puts the peek away.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { store.closePeek() }
                    .allowsHitTesting(isResting)

                backdrop
                    .frame(width: page.width, height: page.height)
                    .clipShape(RoundedRectangle(cornerRadius: store.adaptiveTheme.cardCornerRadius, style: .continuous))
                    .position(x: page.midX, y: page.midY)
                    .opacity(isResting ? 1 : 0)
                    .allowsHitTesting(false)

                card(radius: pose == .filled ? store.adaptiveTheme.cardCornerRadius : 12)
                    .frame(width: rect.width, height: rect.height)
                    .opacity(pose == .seed ? 0 : 1)
                    .position(x: rect.midX, y: rect.midY)

                actions
                    .position(x: resting.maxX + 12 + Self.buttonSize / 2, y: resting.minY + actionsHeight / 2)
                    .opacity(isResting ? 1 : 0)
                    .scaleEffect(isResting ? 1 : 0.8)
                    .allowsHitTesting(isResting)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { isShown = true }
        }
    }

    /// Where the card grows from and shrinks back to: a speck on the press,
    /// or, without one, the resting card a little smaller. A real frame rather
    /// than a scale effect, so the hosted web view is always laid out at the
    /// size it is drawn.
    private func seedRect(from resting: CGRect, space: CGRect) -> CGRect {
        guard let origin = store.peekOrigin else {
            return resting.insetBy(dx: resting.width * 0.04, dy: resting.height * 0.04)
        }
        let size = CGSize(width: resting.width * 0.06, height: resting.height * 0.06)
        return CGRect(
            x: origin.x - space.minX - size.width / 2,
            y: origin.y - space.minY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static let buttonSize: CGFloat = 32

    /// The card in the page, leaving room on the right for its buttons.
    static func restingRect(in page: CGRect) -> CGRect {
        let side = buttonSize + 12 + 16
        let width = max(320, min(page.width - side * 2, 1100))
        let height = max(240, page.height - 24)
        return CGRect(x: page.midX - width / 2, y: page.midY - height / 2, width: width, height: height)
    }

    /// The page behind the card, blurred.
    private var backdrop: some View {
        ZStack {
            VisualEffectBlur(material: .fullScreenUI, blendingMode: .withinWindow)
            Color.black.opacity(store.isDarkMode ? 0.18 : 0.03)
        }
    }

    /// Just the page: no title strip and no outline, only rounded corners and a soft shadow.
    private func card(radius: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // Embedded Content: Error Page or Web View
            if let pageError = tab.pageError {
                PageErrorView(store: store, tab: tab, error: pageError)
                    .id(tab.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WebView(tab: tab)
                    .id(tab.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            PeekProgressBar(tab: tab)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(
            color: Color.black.opacity(store.isDarkMode ? 0.40 : 0.14),
            radius: 24,
            x: 0,
            y: 10
        )
    }

    private var actionsHeight: CGFloat { Self.buttonSize * 2 + 8 }

    private var actions: some View {
        VStack(spacing: 8) {
            // 1. Close peek view
            PeekFloatingActionButton(
                icon: Image(systemName: "xmark"),
                iconSize: 11,
                help: "Close preview (Esc)",
                glass: glass,
                isDark: store.isDarkMode,
                action: { store.closePeek() }
            )

            // 2. Expand peek view as new tab
            PeekFloatingActionButton(
                icon: Image(systemName: "arrow.up.left.and.arrow.down.right"),
                iconSize: 11,
                help: "Open in new tab (⌘⏎)",
                glass: glass,
                isDark: store.isDarkMode,
                action: { store.keepPeek() }
            )
        }
    }
}

// MARK: - Peek progress (scoped tab observation)

/// Hairline loader that alone observes tab progress.
private struct PeekProgressBar: View {
    @ObservedObject var tab: LeanTab

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 2)

            if tab.isLoading {
                GeometryReader { barGeo in
                    let progress = max(0.06, CGFloat(tab.loadingProgress))
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: barGeo.size.width * progress, height: 2)
                }
                .frame(height: 2)
                .transition(.opacity)
            }
        }
        .frame(height: 2)
    }
}

// MARK: - Peek Floating Action Button

private struct PeekFloatingActionButton: View {
    let icon: Image
    let iconSize: CGFloat
    let help: String
    let glass: Bool
    let isDark: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            if glass, #available(macOS 26, *) {
                icon
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
                    .frame(width: PeekPanel.buttonSize, height: PeekPanel.buttonSize)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(Circle())
            } else {
                solidLabel
            }
        }
        .buttonStyle(PeekActionButtonStyle())
        .help(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    /// The glass button's shape and weight, opaque.
    private var solidLabel: some View {
        icon
            .font(.system(size: iconSize, weight: .medium))
            .foregroundColor(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
            .frame(width: PeekPanel.buttonSize, height: PeekPanel.buttonSize)
            .background(
                Circle().fill(
                    isDark
                        ? Color(white: isHovered ? 0.24 : 0.18)
                        : Color(white: isHovered ? 0.93 : 0.98)
                )
            )
            .overlay(Circle().strokeBorder(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(isDark ? 0.3 : 0.1), radius: 6, x: 0, y: 2)
            .contentShape(Circle())
    }
}

private struct PeekActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
