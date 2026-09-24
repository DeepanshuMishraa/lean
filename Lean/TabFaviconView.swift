import SwiftUI

struct TabFaviconView: View {
    @ObservedObject var tab: LeanTab
    let isDark: Bool
    var size: CGFloat = 14

    @Environment(\.browserUIScale) private var browserUIScale

    private var scaledSize: CGFloat { size * browserUIScale }

    private var host: String {
        guard let url = tab.url, let host = url.host?.lowercased() else { return "" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    var body: some View {
        if let image = tab.favicon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: scaledSize, height: scaledSize)
                .clipShape(RoundedRectangle(cornerRadius: 3 * browserUIScale, style: .continuous))
        } else {
            fallbackIcon
                .frame(width: scaledSize, height: scaledSize)
        }
    }

    @ViewBuilder
    private var fallbackIcon: some View {
        if tab.isSettingsPage {
            LeanIcon.gear.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: scaledSize * 0.85, height: scaledSize * 0.85)
                .foregroundColor(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.75))
        } else if tab.url == nil {
            LeanIcon.browser.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: scaledSize * 0.85, height: scaledSize * 0.85)
                .foregroundColor(isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
        } else {
            SiteFallbackGlyph(host: host, isDark: isDark, size: scaledSize)
        }
    }
}

// MARK: - Shared fallback glyph
/// Brand marks plus the initial-letter monogram, shared by TabFaviconView
/// and SiteFaviconView so the two fallback chains can never drift apart.
/// Pure glyph rendering inside the caller's frame: no hit-testing impact.
struct SiteFallbackGlyph: View {
    let host: String
    let isDark: Bool
    var size: CGFloat = 14

    @ViewBuilder
    var body: some View {
        if host.contains("youtube") || host.contains("youtu.be") {
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color(red: 255/255, green: 0, blue: 0))
                LeanIcon.play.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.45, height: size * 0.45)
                    .foregroundColor(.white)
                    .offset(x: 0.5)
            }
        } else if host.contains("x.com") || host.contains("twitter") {
            Text("𝕏")
                .font(.system(size: size * 0.9, weight: .bold))
                .foregroundColor(isDark ? Color.white : Color.black)
        } else if host.contains("github") {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isDark ? Color.white : Color.black)
                LeanIcon.code.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .foregroundColor(isDark ? Color.black : Color.white)
            }
        } else if host.contains("google") {
            ZStack {
                Circle()
                    .fill(Color(red: 66/255, green: 133/255, blue: 244/255))
                Text("G")
                    .font(.system(size: size * 0.65, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        } else if host.contains("apple") {
            LeanIcon.appleLogo.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(isDark ? Color.white : Color.black)
        } else if host.contains("discord") {
            LeanIcon.chats.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.8, height: size * 0.8)
                .foregroundColor(Color(red: 88/255, green: 101/255, blue: 242/255))
        } else if host.contains("slack") {
            LeanIcon.hash.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(Color(red: 224/255, green: 30/255, blue: 90/255))
        } else if host.contains("claude") || host.contains("anthropic") {
            LeanIcon.sparkle.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(Color(red: 217/255, green: 119/255, blue: 87/255))
        } else if host.contains("cloudflare") {
            LeanIcon.cloud.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.8, height: size * 0.8)
                .foregroundColor(Color(red: 243/255, green: 128/255, blue: 32/255))
        } else if host.contains("reddit") {
            LeanIcon.redditLogo.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(Color(red: 255/255, green: 69/255, blue: 0))
        } else if !host.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.08))
                Text(String(host.prefix(1)).uppercased())
                    .font(.system(size: size * 0.62, weight: .semibold, design: .rounded))
                    .foregroundColor(isDark ? Color.white.opacity(0.9) : Color.black.opacity(0.75))
            }
        } else {
            LeanIcon.browser.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(isDark ? Color.white.opacity(0.70) : Color.black.opacity(0.60))
        }
    }
}

// MARK: - Standalone Site Favicon View
struct SiteFaviconView: View {
    let url: URL?
    let isDark: Bool
    var size: CGFloat = 18

    @State private var loadedFavicon: NSImage?
    @Environment(\.browserUIScale) private var browserUIScale

    private var scaledSize: CGFloat { size * browserUIScale }

    private var host: String {
        guard let url = url, let host = url.host?.lowercased() else { return "" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    var body: some View {
        if let image = loadedFavicon ?? FaviconService.shared.cachedFavicon(for: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: scaledSize, height: scaledSize)
                .clipShape(RoundedRectangle(cornerRadius: 3.5 * browserUIScale, style: .continuous))
        } else {
            fallbackIcon
                .frame(width: scaledSize, height: scaledSize)
                .onAppear {
                    FaviconService.shared.loadFavicon(for: url) { img in
                        if let img {
                            self.loadedFavicon = img
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var fallbackIcon: some View {
        if let url = url, url.absoluteString.hasPrefix("lean://settings") {
            LeanIcon.gear.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: scaledSize * 0.85, height: scaledSize * 0.85)
                .foregroundColor(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.75))
        } else if url == nil {
            LeanIcon.browser.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: scaledSize * 0.85, height: scaledSize * 0.85)
                .foregroundColor(isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
        } else {
            SiteFallbackGlyph(host: host, isDark: isDark, size: scaledSize)
        }
    }
}

// MARK: - Tab Media Indicator & Mute Toggle

struct TabMediaIndicatorView: View {
    @ObservedObject var tab: LeanTab
    let theme: AdaptiveFrameTheme
    var compact: Bool = false

    @State private var isHovered = false

    private var iconSize: CGFloat {
        compact ? 8 : 10
    }

    private var containerSize: CGFloat {
        compact ? 14 : 18
    }

    var body: some View {
        Button {
            tab.toggleMute()
        } label: {
            ZStack {
                if isHovered {
                    // Hover state: show the action that clicking will perform
                    (tab.isMuted ? LeanIcon.speaker : LeanIcon.speakerMute).fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                        .foregroundColor(theme.primaryText)
                } else if tab.isMuted {
                    // Muted state: speaker slash icon
                    LeanIcon.speakerMute.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                        .foregroundColor(theme.secondaryText)
                } else {
                    // Active playing state: dynamic 3-bar equalizer
                    EqualizerWaveformView(
                        color: theme.primaryText.opacity(0.88),
                        compact: compact
                    )
                }
            }
            .frame(width: containerSize, height: containerSize)
            .background(
                isHovered
                    ? theme.iconHoverBackground
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: compact ? 3.5 : 4, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tab.isMuted ? "Unmute Tab" : "Mute Tab")
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.10), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: tab.isMuted)
    }
}

/// A lightweight, hardware-accelerated 3-bar equalizer waveform.
private struct EqualizerWaveformView: View {
    let color: Color
    var compact: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let barW: CGFloat = compact ? 1.2 : 1.5
            let spacing: CGFloat = compact ? 1.0 : 1.3
            let minH: CGFloat = compact ? 2.5 : 3.0
            let maxH: CGFloat = compact ? 7.5 : 10.0
            let span = maxH - minH

            let h1 = minH + span * (0.5 + 0.5 * sin(t * 7.0))
            let h2 = minH + span * (0.5 + 0.5 * sin(t * 9.5 + 1.2))
            let h3 = minH + span * (0.5 + 0.5 * sin(t * 6.0 + 2.3))

            HStack(alignment: .bottom, spacing: spacing) {
                Capsule()
                    .fill(color)
                    .frame(width: barW, height: h1)
                Capsule()
                    .fill(color)
                    .frame(width: barW, height: h2)
                Capsule()
                    .fill(color)
                    .frame(width: barW, height: h3)
            }
            .frame(height: maxH, alignment: .bottom)
        }
    }
}


