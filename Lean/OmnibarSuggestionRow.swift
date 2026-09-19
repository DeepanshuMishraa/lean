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

                Text(match.isSearch ? "Search \(match.searchEngine?.name ?? match.secondaryText) for \"\(match.primaryText)\"" : match.primaryText)
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
        if match.isSearch {
            return .search
        }
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
            SearchEngineFaviconView(engine: match.searchEngine ?? .google, isDark: isDark)

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

private struct SearchEngineFaviconView: View {
    let engine: SearchEngine
    let isDark: Bool
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.55))
            }
        }
        .frame(width: 20, height: 20)
        .onAppear {
            image = FaviconService.shared.cachedFavicon(for: engine.searchURL)
            guard image == nil else { return }
            FaviconService.shared.loadFavicon(for: engine.searchURL) { loadedImage in
                image = loadedImage
            }
        }
    }
}

private struct GoogleFaviconView: View {
    private static let googleSVGData: Data = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
        <path fill="#4285F4" d="M23.745 12.27c0-.7-.07-1.4-.19-2.07H12v4.51h6.6c-.29 1.52-1.14 2.82-2.4 3.68v3.05h3.88c2.27-2.09 3.665-5.2 3.665-9.17z"/>
        <path fill="#34A853" d="M12 24c3.24 0 5.95-1.08 7.93-2.91l-3.88-3.05c-1.08.72-2.45 1.16-4.05 1.16-3.12 0-5.77-2.12-6.72-4.97H1.23v3.13C3.26 21.32 7.34 24 12 24z"/>
        <path fill="#FBBC05" d="M5.28 14.23c-.25-.72-.38-1.49-.38-2.23s.13-1.51.38-2.23V6.64H1.23C.45 8.19 0 9.99 0 12s.45 3.81 1.23 5.36l4.05-3.13z"/>
        <path fill="#EA4335" d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0 7.34 0 3.26 2.68 1.23 6.64l4.05 3.13c.95-2.85 3.6-4.97 6.72-4.97z"/>
    </svg>
    """.data(using: .utf8)!

    private static let googleImage: NSImage? = {
        guard let img = NSImage(data: googleSVGData) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        return img
    }()

    var body: some View {
        if let img = Self.googleImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 66/255, green: 133/255, blue: 244/255))
                .frame(width: 16, height: 16)
        }
    }
}
