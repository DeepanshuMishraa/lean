import AppKit
import SwiftUI

/// What the sliders button in the sidebar's address bar opens: actions on
/// the page, the extensions, this site's switches, and how it is connected.
struct SitePopover: View {
    @ObservedObject var store: LeanStore
    @State private var didCopyLink = false
    @State private var isInspectorVisible = false

    private var url: URL? { store.selectedTab?.url }
    private var webHost: String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url.host
    }
    private var ink: Color { store.adaptiveTheme.primaryText }
    private var muted: Color { store.adaptiveTheme.secondaryText }
    private var tileFill: Color { store.isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.05) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            actions
            extensions
            if let webHost { thisSite(host: webHost) }
            Rectangle()
                .fill(store.themeColors.divider)
                .frame(height: 0.75)
            footer
        }
        .padding(14)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(store.adaptiveTheme.dropdownBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(store.adaptiveTheme.dropdownStroke, lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(store.isDarkMode ? 0.4 : 0.15), radius: 22, y: 8)
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { store.sitePopoverFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in store.sitePopoverFrame = frame }
            }
        )
        .onAppear { isInspectorVisible = store.isInspectorVisible }
        .onDisappear { store.sitePopoverFrame = .zero }
    }

    private func dismiss() {
        store.isSitePopoverPresented = false
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            if let url {
                ShareLink(item: url) { tileLabel(Image(systemName: "square.and.arrow.up")) }
                    .buttonStyle(.hitArea)
                    .help("Share")
            } else {
                tileLabel(Image(systemName: "square.and.arrow.up")).opacity(0.4)
            }
            tile(Image(systemName: didCopyLink ? "checkmark" : "link"), help: "Copy Link", enabled: url != nil) {
                guard let url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                Haptics.select()
                didCopyLink = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { didCopyLink = false }
            }
            tile(
                Image(systemName: store.isBookmarked(url: url) ? "star.fill" : "star"),
                help: store.isBookmarked(url: url) ? "Edit Bookmark" : "Bookmark This Page",
                enabled: url != nil
            ) {
                dismiss()
                store.showBookmarkConfirmationDialogForCurrentTab()
            }
            tile(LeanIcon.magnifyingGlass.fill.aspectRatio(contentMode: .fit), help: "Find on Page (⌘F)", enabled: store.selectedTab?.url != nil) {
                dismiss()
                store.showsFindBar = true
            }
        }
    }

    private func tile<Icon: View>(_ icon: Icon, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(icon) }
            .buttonStyle(.hitArea)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
            .help(help)
    }

    private func tileLabel<Icon: View>(_ icon: Icon) -> some View {
        icon
            .font(.system(size: 14, weight: .medium))
            .frame(width: 15, height: 15)
            .foregroundColor(ink)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(tileFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
    }

    // MARK: Extensions

    @ViewBuilder
    private var extensions: some View {
        if #available(macOS 15.4, *) {
            SitePopoverExtensions(store: store, tileFill: tileFill, onOpen: dismiss)
        }
    }

    // MARK: This site

    private func thisSite(host: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This site")
                .font(store.headingFont(size: 12.5))
                .foregroundColor(ink)
            siteToggle(
                icon: Image(systemName: "shield.lefthalf.filled"),
                title: "Block ads and trackers",
                subtitle: !store.adBlockingEnabled ? "Off everywhere" : (store.isAdBlockingEnabled(for: host) ? "On" : "Off"),
                isOn: Binding(
                    get: { store.adBlockingEnabled && store.isAdBlockingEnabled(for: host) },
                    set: { store.setAdBlocking($0, for: host) }
                )
            )
            .disabled(!store.adBlockingEnabled)
            siteToggle(
                icon: Image(systemName: "chevron.left.forwardslash.chevron.right"),
                title: "Developer Mode",
                subtitle: nil,
                isOn: Binding(
                    get: { isInspectorVisible },
                    set: { _ in
                        store.toggleInspector()
                        isInspectorVisible = store.isInspectorVisible
                    }
                )
            )
        }
    }

    private func siteToggle(icon: Image, title: String, subtitle: String?, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            icon
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(muted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(store.bodyFont(size: 12.5))
                    .foregroundColor(ink)
                if let subtitle {
                    Text(subtitle)
                        .font(store.bodyFont(size: 10.5))
                        .foregroundColor(muted)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { isOn.wrappedValue }, set: { value in
                Haptics.select()
                isOn.wrappedValue = value
            }))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let url {
                let secure = url.scheme?.lowercased() == "https"
                HStack(spacing: 6) {
                    LeanIcon.lock.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 10, height: 10)
                    Text(secure ? "Secure" : (url.isFileURL ? "Local file" : "Not secure"))
                        .font(store.headingFont(size: 11.5))
                }
                .foregroundColor(secure ? ink : muted)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(tileFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            Spacer()
            Button {
                dismiss()
                store.isQuickSettingsPresented = true
            } label: {
                LeanIcon.dotsThree.bold
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundColor(muted)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.hitArea)
            .help("More: zen mode, history, private window, settings")
        }
    }
}

@available(macOS 15.4, *)
private struct SitePopoverExtensions: View {
    @ObservedObject var store: LeanStore
    let tileFill: Color
    let onOpen: () -> Void
    @StateObject private var manager = BrowserExtensionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Extensions")
                    .font(store.headingFont(size: 12.5))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                Spacer()
                Button("Manage") {
                    onOpen()
                    store.openSettings(category: .extensions)
                }
                .buttonStyle(.hitArea)
                .font(store.bodyFont(size: 11.5))
                .foregroundColor(store.adaptiveTheme.secondaryText)
            }
            HStack(spacing: 8) {
                ForEach(manager.installed.filter(\.enabled).prefix(4)) { item in
                    Button {
                        onOpen()
                        store.isExtensionsPresented = true
                        if !manager.performAction(item.id) { store.isExtensionsPresented = false }
                    } label: {
                        Group {
                            if let icon = manager.icon(for: item.id) {
                                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                            } else {
                                LeanIcon.extension.fill.aspectRatio(contentMode: .fit)
                                    .foregroundColor(store.adaptiveTheme.secondaryText)
                            }
                        }
                        .frame(width: 18, height: 18)
                        .frame(width: 44, height: 44)
                        .background(tileFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.hitArea)
                    .help(item.name)
                }
                Button {
                    onOpen()
                    store.openSettings(category: .extensions)
                } label: {
                    LeanIcon.plus.bold
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .foregroundColor(store.adaptiveTheme.primaryText)
                        .frame(width: 44, height: 44)
                        .background(tileFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hitArea)
                .help("Add Extensions")
            }
        }
    }
}
