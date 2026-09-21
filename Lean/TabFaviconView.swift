import PhosphorSwift
import SwiftUI

struct TabFaviconView: View {
    @ObservedObject var tab: LeanTab
    let isDark: Bool
    var size: CGFloat = 14

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
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            fallbackIcon
                .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private var fallbackIcon: some View {
        if tab.isSettingsPage {
            Ph.browser.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.75))
        } else if tab.url == nil {
            Ph.browser.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
        } else if host.contains("youtube") || host.contains("youtu.be") {
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color(red: 255/255, green: 0, blue: 0))
                Ph.play.fill
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
                Ph.code.fill
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
            Ph.appleLogo.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(isDark ? Color.white : Color.black)
        } else if host.contains("discord") {
            Ph.chats.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.8, height: size * 0.8)
                .foregroundColor(Color(red: 88/255, green: 101/255, blue: 242/255))
        } else if host.contains("slack") {
            Ph.hash.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(Color(red: 224/255, green: 30/255, blue: 90/255))
        } else if host.contains("claude") || host.contains("anthropic") {
            Ph.sparkle.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(Color(red: 217/255, green: 119/255, blue: 87/255))
        } else if host.contains("cloudflare") {
            Ph.cloud.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.8, height: size * 0.8)
                .foregroundColor(Color(red: 243/255, green: 128/255, blue: 32/255))
        } else if host.contains("reddit") {
            Ph.redditLogo.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(Color(red: 255/255, green: 69/255, blue: 0))
        } else if !host.isEmpty {
            // Initial letter badge
            let initial = String(host.prefix(1)).uppercased()
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                Text(initial)
                    .font(.system(size: size * 0.65, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? Color.white.opacity(0.8) : Color.black.opacity(0.7))
            }
        } else {
            Ph.browser.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
        }
    }
}

// MARK: - Standalone Site Favicon View
struct SiteFaviconView: View {
    let url: URL?
    let isDark: Bool
    var size: CGFloat = 18

    @State private var loadedFavicon: NSImage?

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
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        } else {
            fallbackIcon
                .frame(width: size, height: size)
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
            Ph.browser.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.75))
        } else if url == nil {
            Ph.browser.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
        } else if host.contains("youtube") || host.contains("youtu.be") {
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color(red: 255/255, green: 0, blue: 0))
                Ph.play.fill
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
                Ph.code.fill
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
            Ph.appleLogo.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(isDark ? Color.white : Color.black)
        } else if host.contains("discord") {
            Ph.chats.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.8, height: size * 0.8)
                .foregroundColor(Color(red: 88/255, green: 101/255, blue: 242/255))
        } else if host.contains("slack") {
            Ph.hash.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(Color(red: 224/255, green: 30/255, blue: 90/255))
        } else if host.contains("claude") || host.contains("anthropic") {
            Ph.sparkle.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(Color(red: 217/255, green: 119/255, blue: 87/255))
        } else if host.contains("cloudflare") {
            Ph.cloud.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.8, height: size * 0.8)
                .foregroundColor(Color(red: 243/255, green: 128/255, blue: 32/255))
        } else if host.contains("reddit") {
            Ph.redditLogo.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(Color(red: 255/255, green: 69/255, blue: 0))
        } else if !host.isEmpty {
            let initial = String(host.prefix(1)).uppercased()
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                Text(initial)
                    .font(.system(size: size * 0.65, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? Color.white.opacity(0.8) : Color.black.opacity(0.7))
            }
        } else {
            Ph.browser.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .foregroundColor(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
        }
    }
}

