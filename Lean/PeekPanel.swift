//
//  PeekPanel.swift
//  Lean
//
//  A bespoke, high-polish link preview panel designed for Shift-click peeking.
//  Ultra-clean, minimal aesthetic with buttery smooth physical spring transitions,
//  live loading indicator, navigation controls, and direct tab promotion.
//

import AppKit
import SwiftUI

/// The link preview panel floating over the page with a clean backdrop scrim.
struct PeekPanel: View {
    @ObservedObject var store: LeanStore
    @ObservedObject var tab: LeanTab

    @State private var hasCopied = false
    @State private var copyTask: Task<Void, Never>? = nil

    private var cardBackground: Color {
        store.isDarkMode
            ? Color(red: 20/255, green: 20/255, blue: 23/255)
            : Color(white: 0.99)
    }

    private var headerBackground: Color {
        store.isDarkMode
            ? Color(red: 25/255, green: 25/255, blue: 29/255)
            : Color(white: 0.965)
    }

    private var headerBorder: Color {
        store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var displayTitle: String {
        let trimmed = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let host = tab.url?.host { return host }
        return "Preview"
    }

    private var displayHost: String {
        guard let host = tab.url?.host?.lowercased() else { return "" }
        let clean = host.replacingOccurrences(of: "www.", with: "")
        if let path = tab.url?.path, path != "/", !path.isEmpty {
            return clean + path
        }
        return clean
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(max(660, geo.size.width * 0.80), 1080)
            let cardHeight = min(max(460, geo.size.height * 0.83), 780)

            ZStack {
                // Dimming Scrim with subtle blur
                ZStack {
                    Color.black.opacity(store.isDarkMode ? 0.45 : 0.26)
                    VisualEffectBlur(material: .fullScreenUI, blendingMode: .withinWindow)
                        .opacity(store.isDarkMode ? 0.35 : 0.18)
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    store.closePeek()
                }
                .transition(.opacity)

                // Centered Preview Card with Physical Spring Transition
                VStack(spacing: 0) {
                    headerBar

                    // Sleek Hairline Loading Indicator
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(headerBorder)
                            .frame(height: 0.75)

                        if tab.isLoading {
                            GeometryReader { barGeo in
                                let progress = max(0.06, CGFloat(tab.loadingProgress))
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.blue.opacity(0.75),
                                                Color.blue
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: barGeo.size.width * progress, height: 2)
                                    .animation(.easeInOut(duration: 0.18), value: tab.loadingProgress)
                            }
                            .frame(height: 2)
                            .transition(.opacity)
                        }
                    }
                    .frame(height: 2)

                    // Embedded Web View
                    WebView(tab: tab)
                        .id(tab.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: cardWidth, height: cardHeight)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                            lineWidth: 0.75
                        )
                )
                .shadow(
                    color: Color.black.opacity(store.isDarkMode ? 0.55 : 0.18),
                    radius: 38,
                    x: 0,
                    y: 16
                )
                .shadow(
                    color: Color.black.opacity(store.isDarkMode ? 0.28 : 0.06),
                    radius: 10,
                    x: 0,
                    y: 4
                )
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

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 10) {
            // Navigation Controls: Back / Forward / Reload
            HStack(spacing: 2) {
                PeekHeaderIconButton(
                    icon: .caretLeft,
                    help: "Back",
                    isEnabled: tab.canGoBack,
                    isDark: store.isDarkMode
                ) {
                    tab.goBack()
                }

                PeekHeaderIconButton(
                    icon: .caretRight,
                    help: "Forward",
                    isEnabled: tab.canGoForward,
                    isDark: store.isDarkMode
                ) {
                    tab.goForward()
                }

                PeekHeaderIconButton(
                    icon: .arrowClockwise,
                    help: "Reload",
                    isEnabled: true,
                    isDark: store.isDarkMode
                ) {
                    tab.reload()
                }
            }

            Rectangle()
                .fill(headerBorder)
                .frame(width: 0.75, height: 16)
                .padding(.horizontal, 2)

            // Site Identity: Favicon + Title + Host
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        .frame(width: 22, height: 22)

                    SiteFaviconView(
                        url: tab.url,
                        isDark: store.isDarkMode,
                        size: 13
                    )
                }

                VStack(alignment: .leading, spacing: 0.5) {
                    Text(displayTitle)
                        .font(store.headingFont(size: 12.5, weight: .semibold))
                        .foregroundColor(store.adaptiveTheme.primaryText)
                        .lineLimit(1)

                    if !displayHost.isEmpty {
                        Text(displayHost)
                            .font(store.bodyFont(size: 10.5))
                            .foregroundColor(store.adaptiveTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 12)

            // Actions: Copy Link, Open as Tab, Close
            HStack(spacing: 6) {
                // Copy Link Button
                Button(action: copyLink) {
                    HStack(spacing: 4.5) {
                        (hasCopied ? LeanIcon.check.bold : LeanIcon.copy.fill)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10.5, height: 10.5)
                            .foregroundColor(hasCopied ? Color.green : store.adaptiveTheme.secondaryText)

                        Text(hasCopied ? "Copied" : "Copy")
                            .font(store.bodyFont(size: 11, weight: .medium))
                            .foregroundColor(hasCopied ? Color.green : store.adaptiveTheme.secondaryText)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(headerBorder, lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)
                .help("Copy URL")

                // Open as Tab Button (Primary action)
                Button(action: { store.keepPeek() }) {
                    HStack(spacing: 5) {
                        LeanIcon.arrowSquareOut.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10.5, height: 10.5)

                        Text("Open as Tab")
                            .font(store.bodyFont(size: 11, weight: .medium))

                        Text("⌘⏎")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .opacity(0.65)
                    }
                    .foregroundColor(store.isDarkMode ? Color.white : Color.black)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                store.isDarkMode ? Color.white.opacity(0.16) : Color.black.opacity(0.12),
                                lineWidth: 0.75
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("Open in new tab (⌘⏎)")

                // Close Button
                Button(action: { store.closePeek() }) {
                    LeanIcon.x.bold
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 9.5, height: 9.5)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                        .overlay(
                            Circle()
                                .stroke(headerBorder, lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
                .help("Close preview (Esc)")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(headerBackground)
    }

    private func copyLink() {
        guard let url = tab.url?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)

        withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
            hasCopied = true
        }

        copyTask?.cancel()
        copyTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.18)) {
                        hasCopied = false
                    }
                }
            }
        }
    }
}

// MARK: - Header Icon Button
private struct PeekHeaderIconButton: View {
    let icon: LeanIcon
    let help: String
    let isEnabled: Bool
    let isDark: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            icon.bold
                .aspectRatio(contentMode: .fit)
                .frame(width: 10, height: 10)
                .foregroundColor(
                    isEnabled
                        ? (isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.80))
                        : (isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.22))
                )
                .frame(width: 24, height: 24)
                .background(
                    isHovered && isEnabled
                        ? (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .onHover { isHovered = $0 }
    }
}
