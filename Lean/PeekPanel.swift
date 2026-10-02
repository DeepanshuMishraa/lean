//
//  PeekPanel.swift
//  Lean
//
//  A bespoke, high-polish link preview panel designed for Shift-click peeking.
//  Clean modal preview card with floating action controls:
//  - Close preview
//  - Expand as new tab
//  - Open in split view
//

import AppKit
import SwiftUI

/// The link preview panel floating over the page with a clean backdrop scrim.
struct PeekPanel: View {
    @ObservedObject var store: LeanStore
    /// Plain ref on purpose: only the tiny `PeekProgressBar`
    /// subview observes the tab, so progress ticks (10Hz) don't re-evaluate
    /// this whole card + its hosted WebView + the scrim GeometryReader.
    let tab: LeanTab

    private var cardBackground: Color {
        store.glassActive ? Color.clear : store.isDarkMode
            ? Color(red: 20/255, green: 20/255, blue: 23/255)
            : Color(white: 0.99)
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(max(640, geo.size.width * 0.80), min(1080, geo.size.width - 130))
            let cardHeight = min(max(460, geo.size.height * 0.83), 820)

            ZStack {
                // Dim backdrop scrim: tapping outside closes the peek view
                Color.black.opacity(store.isDarkMode ? 0.45 : 0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.closePeek()
                    }
                    .transition(.opacity)

                // Centered Preview Card with Floating Actions on the side
                HStack(alignment: .top, spacing: 14) {
                    // Balancing spacer on the leading side so the preview card remains mathematically centered
                    Color.clear
                        .frame(width: 36)
                        .allowsHitTesting(false)

                    // Preview Card + top indicator pill
                    VStack(spacing: 8) {
                        Capsule()
                            .fill(Color.white.opacity(0.38))
                            .frame(width: 36, height: 4)

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
                        .frame(width: cardWidth, height: cardHeight)
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .leanGlassIf(store.glassActive, radius: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                                    lineWidth: 0.75
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(store.isDarkMode ? 0.50 : 0.22),
                            radius: 32,
                            x: 0,
                            y: 16
                        )
                    }

                    // Floating action buttons on the right side
                    VStack(spacing: 10) {
                        // 1. Close peek view
                        PeekFloatingActionButton(
                            icon: Image(systemName: "xmark"),
                            iconSize: 13,
                            help: "Close preview (Esc)",
                            action: { store.closePeek() }
                        )

                        // 2. Expand peek view as new tab
                        PeekFloatingActionButton(
                            icon: Image(systemName: "arrow.up.right.and.arrow.down.left"),
                            iconSize: 14,
                            help: "Open in new tab (⌘⏎)",
                            action: { store.keepPeek() }
                        )

                        // 3. Create split view with this tab and the tab from which it was called
                        PeekFloatingActionButton(
                            icon: Image(systemName: "rectangle.split.2x1"),
                            iconSize: 15,
                            help: "Open in split view (⌘⌥⏎)",
                            action: { store.splitPeek() }
                        )
                    }
                    .padding(.top, 12)
                }
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.94)
                            .combined(with: .offset(y: 16))
                            .combined(with: .opacity),
                        removal: .scale(scale: 0.96)
                            .combined(with: .offset(y: 10))
                            .combined(with: .opacity)
                    )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            icon
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(Color.white.opacity(isHovered ? 1.0 : 0.88))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(
                            isHovered
                                ? Color(white: 0.28).opacity(0.95)
                                : Color(white: 0.14).opacity(0.85)
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            Color.white.opacity(isHovered ? 0.32 : 0.16),
                            lineWidth: 0.75
                        )
                )
                .shadow(
                    color: Color.black.opacity(0.35),
                    radius: 8,
                    x: 0,
                    y: 3
                )
                .scaleEffect(isHovered ? 1.06 : 1.0)
                .contentShape(Circle())
        }
        .buttonStyle(PeekActionButtonStyle())
        .help(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

private struct PeekActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
