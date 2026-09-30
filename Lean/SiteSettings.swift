import SwiftUI
import WebKit

/// Shared animation curves. Short and without overshoot: the tab row is
/// used constantly, so a switch should settle, not bounce.
enum Motion {
    static let tabSwitch = Animation.spring(response: 0.3, dampingFraction: 0.9)
    static let quick = Animation.easeOut(duration: 0.16)
}

/// Which sites may play sound by themselves. WebKit takes the choice for each
/// page as it loads, through the page's preferences, under a name outside
/// the public framework: asked for first, so a WebKit without it just leaves
/// the site waiting for a click. Values: 0 default, 1 allow, 2 allow without
/// sound, 3 deny. Off stores nothing.
enum SiteAutoplay {
    private static func key(_ host: String) -> String { "autoplay." + host }

    static func allowed(_ host: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(host))
    }

    static func set(_ on: Bool, for host: String) {
        if on {
            UserDefaults.standard.set(true, forKey: key(host))
        } else {
            UserDefaults.standard.removeObject(forKey: key(host))
        }
    }

    /// For a page about to load at `url`: allowed to play, or left alone.
    static func apply(to preferences: WKWebpagePreferences, for url: URL) {
        guard let host = url.host(), allowed(host) else { return }
        let setter = NSSelectorFromString("_setAutoplayPolicy:")
        guard preferences.responds(to: setter) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Int) -> Void
        unsafeBitCast(preferences.method(for: setter), to: Setter.self)(preferences, setter, 1)
    }
}

/// What a click on the tab you are on shows under its address: whether the
/// connection is private, and the few things that belong to this page.
struct SiteCardView: View {
    @ObservedObject var store: LeanStore
    @ObservedObject var tab: LeanTab
    let url: URL
    let width: CGFloat

    @State private var isConnectionOpen = false

    private var host: String? {
        guard let host = url.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var title: String {
        host ?? (url.isFileURL ? "File" : (url.scheme ?? url.absoluteString))
    }

    private var isSecure: Bool? {
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return false
        default: return nil
        }
    }

    var body: some View {
        Group {
            if isConnectionOpen, let isSecure {
                connectionDetail(isSecure: isSecure)
                    .transition(.opacity)
            } else {
                front
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .frame(width: width)
        .animation(Motion.quick, value: isConnectionOpen)
        .leanPopoverSurface(glass: store.glassActive, isDark: store.isDarkMode, stroke: store.adaptiveTheme.dropdownStroke, fill: store.themeColors.palette?.raised)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { store.inlineSuggestionsFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in
                        store.inlineSuggestionsFrame = frame
                    }
            }
        )
        .onHover { store.isPointerOverSiteCard = $0 }
        .onDisappear {
            store.inlineSuggestionsFrame = .zero
            store.isPointerOverSiteCard = false
        }
    }

    // MARK: - Front

    private var front: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(store.headingFont(size: 11.5))
                .foregroundColor(store.adaptiveTheme.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 26, alignment: .leading)

            if let isSecure {
                SiteCardRow(store: store, title: isSecure ? "Connection is secure" : "Connection is not secure", showsChevron: true) {
                    isConnectionOpen = true
                }
            }
            SiteCardRow(store: store, title: "Copy Address", keys: "⇧⌘C") {
                store.copyAddress()
                store.dismissInlineURLEditing()
            }

            divider

            SiteCardRow(store: store, title: "Print…", keys: "⌘P") {
                store.dismissInlineURLEditing()
                tab.printPage()
            }
            zoomRow
            if let host, isSecure != nil {
                SiteSoundRow(store: store, host: host)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(store.themeColors.divider)
            .frame(height: 0.75)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
    }

    private var zoomRow: some View {
        HStack(spacing: 0) {
            Text("Zoom")
                .font(store.headingFont(size: 12.5))
                .foregroundColor(store.adaptiveTheme.primaryText)
            Spacer(minLength: 16)
            SiteCardStep(store: store, symbol: "minus", help: "Zoom Out", action: tab.zoomOut)
            Button(action: tab.resetZoom) {
                Text("\(Int((tab.pageZoom * 100).rounded()))%")
                    .font(store.bodyFont(size: 12.5))
                    .monospacedDigit()
                    .foregroundColor(store.adaptiveTheme.secondaryText)
                    .frame(width: 44, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.hitArea)
            .help("Actual Size")
            SiteCardStep(store: store, symbol: "plus", help: "Zoom In", action: tab.zoomIn)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    // MARK: - Connection

    private func connectionDetail(isSecure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isConnectionOpen = false
            } label: {
                HStack(spacing: 4) {
                    LeanIcon.caretLeft.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 9, height: 9)
                    Text(title)
                        .font(store.headingFont(size: 11.5))
                }
                .foregroundColor(store.adaptiveTheme.secondaryText)
                .padding(.horizontal, 14)
                .frame(height: 26, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.hitArea)

            Text(isSecure ? "Connection is secure" : "Connection is not secure")
                .font(store.headingFont(size: 12.5))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .padding(.horizontal, 14)
            Text(isSecure
                 ? "What you send to \(title), like passwords or card numbers, is encrypted and can't be read by anyone along the way."
                 : "What you send to \(title) isn't encrypted. Others on the network could read it, so don't enter passwords or card numbers here.")
                .font(store.bodyFont(size: 11.5))
                .foregroundColor(store.adaptiveTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }
}

private struct SiteCardRow: View {
    @ObservedObject var store: LeanStore
    let title: String
    var keys: String? = nil
    var showsChevron = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(store.headingFont(size: 12.5))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                Spacer(minLength: 16)
                if let keys {
                    Text(keys)
                        .font(store.bodyFont(size: 12))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                }
                if showsChevron {
                    LeanIcon.caretRight.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 8, height: 8)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                isHovered ? (store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06)) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.hitArea)
        .onHover { isHovered = $0 }
    }
}

private struct SiteCardStep: View {
    @ObservedObject var store: LeanStore
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovered ? store.adaptiveTheme.primaryText : store.adaptiveTheme.secondaryText)
                .frame(width: 24, height: 24)
                .background(
                    isHovered ? (store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.07)) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.hitArea)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// Whether the site may play sound by itself. WebKit takes it as a page
/// loads, so a page already open stays as it came; the row says so.
private struct SiteSoundRow: View {
    @ObservedObject var store: LeanStore
    let host: String

    private let was: Bool
    @State private var isOn: Bool

    init(store: LeanStore, host: String) {
        self.store = store
        self.host = host
        was = SiteAutoplay.allowed(host)
        _isOn = State(initialValue: was)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Play Sound by Itself")
                .font(store.headingFont(size: 12.5))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .fixedSize()
            Spacer(minLength: 12)
            if isOn != was {
                Text("next page")
                    .font(store.bodyFont(size: 10.5))
                    .foregroundColor(store.adaptiveTheme.secondaryText)
                    .fixedSize()
            }
            TactileSwitch(isOn: $isOn, isDark: store.isDarkMode)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .onChange(of: isOn) { _, value in SiteAutoplay.set(value, for: host) }
    }
}
