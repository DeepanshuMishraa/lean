import AppKit
import SwiftUI

// MARK: - Suggestion Row matching Reference Screenshot
struct SuggestionRow: View {
    let match: OmnibarSuggestion
    let isSelected: Bool
    @ObservedObject var store: LeanStore
    let onSelect: () -> Void
    let onHover: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                BrandFaviconView(match: match, isSelected: isSelected, isDark: store.isDarkMode)
                    .frame(width: 22, height: 22)

                Text(match.isSearch ? "Search Google for \"\(match.primaryText)\"" : match.primaryText)
                    .font(store.leanUIFont.font(size: 13.5, weight: .medium))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if match.isSwitchToTab {
                    switchToTabBadge
                } else if !match.secondaryText.isEmpty && !match.isSearch {
                    Text(match.secondaryText)
                        .font(store.leanUIFont.font(size: 12.5))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovered
            }
            if hovered {
                onHover()
            }
        }
    }

    private var titleColor: Color {
        if isSelected {
            return store.isDarkMode ? Color.white : Color.black
        }
        return store.isDarkMode ? Color.white.opacity(0.9) : Color.black.opacity(0.85)
    }

    private var secondaryTextColor: Color {
        store.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.35)
    }

    private var rowBackground: Color {
        if isSelected {
            return store.isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        }
        if isHovered {
            return store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.03)
        }
        return Color.clear
    }

    private var switchToTabBadge: some View {
        HStack(spacing: 6) {
            Text("Switch to Tab")
                .font(store.leanUIFont.font(size: 12.5, weight: .medium))
                .foregroundColor(
                    isSelected
                        ? (store.isDarkMode ? Color.white : Color.black)
                        : (store.isDarkMode ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
                )

            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        isSelected
                            ? (store.isDarkMode ? Color.white : Color.black)
                            : (store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    )
                    .frame(width: 22, height: 22)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: isSelected ? .bold : .semibold))
                    .foregroundColor(
                        isSelected
                            ? (store.isDarkMode ? Color.black : Color.white)
                            : (store.isDarkMode ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                    )
            }
        }
    }
}

// MARK: - Brand Favicon View
private struct BrandFaviconView: View {
    let match: OmnibarSuggestion
    let isSelected: Bool
    let isDark: Bool

    private enum BrandType {
        case github, youtube, x, cloudflare, discord, claude, google, slack, apple, contact, search, generic
    }

    private var brand: BrandType {
        let text = (match.primaryText + " " + match.secondaryText + " " + match.targetURL.absoluteString).lowercased()
        if text.contains("youtube") || text.contains("youtu.be") { return .youtube }
        if text.contains("x.com") || text.contains("twitter") || match.primaryText.lowercased().contains("on x") { return .x }
        if text.contains("github") { return .github }
        if text.contains("cloudflare") { return .cloudflare }
        if text.contains("discord") { return .discord }
        if text.contains("claude.ai") || text.contains("anthropic") { return .claude }
        if text.contains("slack") { return .slack }
        if text.contains("apple") { return .apple }
        if text.contains("google") { return .google }
        if text.contains("contact") || text.contains("team") { return .contact }
        if match.isSearch { return .search }
        return .generic
    }

    var body: some View {
        switch brand {
        case .github:
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isDark ? Color.white : Color.black)
                    .frame(width: 20, height: 20)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 8.5, weight: .black))
                    .foregroundColor(isDark ? Color.black : Color.white)
            }

        case .youtube:
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(red: 255/255, green: 0, blue: 0))
                    .frame(width: 20, height: 14)
                Image(systemName: "play.fill")
                    .font(.system(size: 6.5))
                    .foregroundColor(.white)
                    .offset(x: 0.5)
            }

        case .x:
            Text("𝕏")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isDark ? Color.white : Color.black)

        case .cloudflare:
            Image(systemName: "cloud.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 243/255, green: 128/255, blue: 32/255))

        case .discord:
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 88/255, green: 101/255, blue: 242/255))

        case .claude:
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 217/255, green: 119/255, blue: 87/255))

        case .slack:
            Image(systemName: "number")
                .font(.system(size: 14, weight: .black))
                .foregroundColor(Color(red: 224/255, green: 30/255, blue: 90/255))

        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isDark ? Color.white : Color.black)

        case .google:
            GoogleFaviconView()

        case .contact:
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 13))
                .foregroundColor(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))

        case .search:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))

        case .generic:
            if match.isSwitchToTab {
                Image(systemName: "macwindow")
                    .font(.system(size: 13))
                    .foregroundColor(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundColor(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
            }
        }
    }
}

private struct GoogleFaviconView: View {
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "globe")
                    .foregroundColor(Color(red: 66/255, green: 133/255, blue: 244/255))
            }
        }
        .frame(width: 16, height: 16)
        .onAppear {
            let googleURL = URL(string: "https://www.google.com")
            if let cached = FaviconService.shared.cachedFavicon(for: googleURL) {
                image = cached
                return
            }
            FaviconService.shared.loadFavicon(for: googleURL) { loadedImage in
                image = loadedImage
            }
        }
    }
}
