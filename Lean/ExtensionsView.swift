import SwiftUI
import WebKit

// MARK: - Bespoke Extensions Popover
struct ExtensionsPopover: View {
    @ObservedObject var store: LeanStore

    var body: some View {
        if #available(macOS 15.4, *) {
            ExtensionsPopoverContent(store: store)
        } else {
            ExtensionsPopoverFallback(store: store)
        }
    }
}

private struct ExtensionsPopoverFallback: View {
    @ObservedObject var store: LeanStore

    var body: some View {
        VStack(spacing: 8) {
            LeanIcon.extension.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(store.adaptiveTheme.secondaryText)
            Text("Extensions require macOS 15.4 or later.")
                .font(store.headingFont(size: 12))
                .foregroundColor(store.adaptiveTheme.primaryText)
        }
        .padding(16)
        .frame(width: 260)
        .background(
            (store.isDarkMode
                ? Color(red: 18 / 255, green: 18 / 255, blue: 21 / 255)
                : Color(white: 0.995)
            ).opacity(0.97)
        )
        .background(VisualEffectBlur(material: .popover, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(store.adaptiveTheme.dropdownStroke, lineWidth: 0.75)
        )
    }
}

@available(macOS 15.4, *)
private struct ExtensionsPopoverContent: View {
    @ObservedObject var store: LeanStore
    @StateObject private var manager = BrowserExtensionManager.shared
    @State private var selectedExtensionID: String? = nil
    @State private var isFooterHovered = false
    @State private var isStoreButtonHovered = false
    @State private var isConfirmingRemove = false
    @State private var isBackHovered = false

    private var activeCount: Int {
        manager.installed.filter(\.enabled).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let selectedID = selectedExtensionID,
               let item = manager.installed.first(where: { $0.id == selectedID }) {
                detailStackView(item: item)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .trailing))
                    ))
            } else {
                rootListView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .leading)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
            }
        }
        .padding(8)
        .frame(width: 320)
        .background(
            (store.isDarkMode
                ? Color(red: 18 / 255, green: 18 / 255, blue: 21 / 255)
                : Color(white: 0.995)
            ).opacity(0.97)
        )
        .background(
            VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(store.adaptiveTheme.dropdownStroke, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(store.isDarkMode ? 0.45 : 0.12), radius: 18, x: 0, y: 8)
        .shadow(color: Color.black.opacity(store.isDarkMode ? 0.20 : 0.04), radius: 2, x: 0, y: 1)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        store.extensionsPopoverFrame = proxy.frame(in: .global)
                    }
                    .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                        store.extensionsPopoverFrame = newFrame
                    }
            }
        )
        .onDisappear {
            store.extensionsPopoverFrame = .zero
            selectedExtensionID = nil
        }
    }

    // MARK: - Root List View
    private var rootListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Text("Extensions")
                    .font(store.headingFont(size: 12.5))
                    .foregroundColor(store.adaptiveTheme.primaryText)

                if activeCount > 0 {
                    Text("\(activeCount) active")
                        .font(store.bodyFont(size: 10.5))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                            in: Capsule()
                        )
                }

                Spacer()

                Button {
                    if let url = URL(string: "https://chromewebstore.google.com/") {
                        store.openURL(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        LeanIcon.arrowSquareOut.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10, height: 10)
                        Text("Store")
                            .font(store.bodyFont(size: 11))
                    }
                    .foregroundColor(isStoreButtonHovered ? store.adaptiveTheme.primaryText : store.adaptiveTheme.secondaryText)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(
                        isStoreButtonHovered
                            ? (store.isDarkMode ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .onHover { isStoreButtonHovered = $0 }
                .help("Open Chrome Web Store")
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)

            // Content
            if manager.installed.isEmpty {
                VStack(spacing: 8) {
                    LeanIcon.extension.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.7))
                    Text("No extensions installed")
                        .font(store.headingFont(size: 12))
                        .foregroundColor(store.adaptiveTheme.primaryText)
                    Text("Add extensions from the Chrome Web Store or load an unpacked folder.")
                        .font(store.bodyFont(size: 11))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else if manager.installed.count > 5 {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(manager.installed) { item in
                            ExtensionPopoverRow(
                                item: item,
                                store: store,
                                manager: manager,
                                onSelectOptions: {
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                        selectedExtensionID = item.id
                                    }
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 260)
            } else {
                VStack(spacing: 2) {
                    ForEach(manager.installed) { item in
                        ExtensionPopoverRow(
                            item: item,
                            store: store,
                            manager: manager,
                            onSelectOptions: {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                    selectedExtensionID = item.id
                                }
                            }
                        )
                    }
                }
            }

            Rectangle()
                .fill(store.themeColors.divider)
                .frame(height: 0.75)
                .padding(.vertical, 2)

            // Footer → full Extensions settings
            Button {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                    store.isExtensionsPresented = false
                }
                store.openSettings(category: .extensions)
            } label: {
                HStack(spacing: 8) {
                    LeanIcon.extension.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                    Text("Manage Extensions…")
                        .font(store.headingFont(size: 12))
                    Spacer()
                    LeanIcon.caretRight.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 8, height: 8)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                }
                .foregroundColor(store.adaptiveTheme.primaryText)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    isFooterHovered
                        ? (store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isFooterHovered = $0 }
        }
    }

    // MARK: - Detail Stack View (In-Popover Extension Options)
    private func detailStackView(item: BrowserExtensionManager.Installed) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top Navigation Bar with Back Button
            HStack(spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.84)) {
                        selectedExtensionID = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        LeanIcon.caretLeft.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10, height: 10)
                        Text("Extensions")
                            .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(isBackHovered ? store.adaptiveTheme.primaryText : store.adaptiveTheme.secondaryText)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(
                        isBackHovered
                            ? (store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.055))
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .onHover { isBackHovered = $0 }

                Spacer()

                // Status Indicator
                let isRunning = manager.loadedIDs.contains(item.id)
                HStack(spacing: 4) {
                    Circle()
                        .fill(isRunning ? Color.green : (item.enabled ? Color.blue : Color.gray.opacity(0.5)))
                        .frame(width: 6, height: 6)
                    Text(isRunning ? "Running" : (item.enabled ? "Active" : "Stopped"))
                        .font(store.bodyFont(size: 10))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                    in: Capsule()
                )
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            // Extension Header Card
            HStack(spacing: 10) {
                extensionIcon(for: item.id, size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(store.headingFont(size: 12.5))
                        .foregroundColor(store.adaptiveTheme.primaryText)
                        .lineLimit(1)
                    Text("Version \(item.version) · \(item.fromStore == true ? "Web Store" : "Unpacked")")
                        .font(store.bodyFont(size: 10))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                TactileSwitch(
                    isOn: Binding(
                        get: { item.enabled },
                        set: { manager.setEnabled(item.id, to: $0) }
                    ),
                    isDark: store.isDarkMode
                )
            }
            .padding(8)
            .background(
                store.isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

            // Action Pills
            HStack(spacing: 6) {
                popoverActionButton(title: "Reload", icon: .arrowClockwise) {
                    manager.reload(item.id)
                }

                if item.fromStore == true {
                    popoverActionButton(title: "Store", icon: .arrowSquareOut) {
                        if let url = URL(string: "https://chromewebstore.google.com/detail/\(item.id)") {
                            store.openURL(url)
                        }
                    }
                } else {
                    popoverActionButton(title: "Finder", icon: .folder) {
                        manager.revealInFinder(item.id)
                    }
                }
            }

            // Permissions section (compact)
            let totalPermsCount = item.requiredPermissions.count + item.optionalPermissions.count + item.requiredHosts.count
            if totalPermsCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions & Access")
                        .font(store.leanUIFont.font(size: 10.5, weight: .medium))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .padding(.top, 2)

                    let permissionsContent = VStack(spacing: 3) {
                        ForEach(item.requiredPermissions, id: \.self) { perm in
                            // Required nativeMessaging is consent given at
                            // install (re-granted on every load): showing it
                            // revocable would refuse a helper the user
                            // already approved. Optional stays revocable.
                            if perm == WKWebExtension.Permission.nativeMessaging.rawValue {
                                permissionRow(
                                    title: "\(perm) (required)",
                                    isOn: .constant(true)
                                )
                                .disabled(true)
                                .opacity(0.75)
                            } else {
                                permissionRow(
                                    title: perm,
                                    isOn: Binding(
                                        get: { item.grantedPermissions.contains(perm) },
                                        set: { manager.setPermission(perm, enabled: $0, for: item.id) }
                                    )
                                )
                            }
                        }
                        ForEach(item.optionalPermissions, id: \.self) { perm in
                            permissionRow(
                                title: "\(perm) (optional)",
                                isOn: Binding(
                                    get: { item.grantedPermissions.contains(perm) },
                                    set: { manager.setPermission(perm, enabled: $0, for: item.id) }
                                )
                            )
                        }
                        ForEach(item.requiredHosts, id: \.self) { host in
                            permissionRow(
                                title: host,
                                isOn: Binding(
                                    get: { item.grantedHosts.contains(host) },
                                    set: { manager.setHost(host, enabled: $0, for: item.id) }
                                )
                            )
                        }
                    }

                    if totalPermsCount > 4 {
                        ScrollView(.vertical, showsIndicators: false) {
                            permissionsContent
                        }
                        .frame(maxHeight: 120)
                    } else {
                        permissionsContent
                    }
                }
            }

            // Diagnostics errors
            if let diagnostics = manager.errors[item.id], !diagnostics.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diagnostics")
                        .font(store.leanUIFont.font(size: 10.5, weight: .medium))
                        .foregroundColor(.red.opacity(0.85))
                    ForEach(Array(diagnostics.prefix(2).enumerated()), id: \.offset) { _, diag in
                        Text(diag)
                            .font(store.bodyFont(size: 9.5))
                            .foregroundColor(.red.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.red.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            }

            Rectangle()
                .fill(store.themeColors.divider)
                .frame(height: 0.75)
                .padding(.vertical, 2)

            // Remove Extension Row
            Button {
                isConfirmingRemove = true
            } label: {
                HStack(spacing: 6) {
                    LeanIcon.trash.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)
                    Text("Remove Extension…")
                        .font(store.leanUIFont.font(size: 11.5, weight: .regular))
                    Spacer()
                }
                .foregroundColor(.red.opacity(0.85))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    Color.red.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "Remove \(item.name)?",
                isPresented: $isConfirmingRemove,
                titleVisibility: .visible
            ) {
                Button("Remove Extension", role: .destructive) {
                    manager.remove(item.id)
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.84)) {
                        selectedExtensionID = nil
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove \"\(item.name)\" and delete its data.")
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers
    private func popoverActionButton(title: String, icon: LeanIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                icon.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(store.leanUIFont.font(size: 11))
            }
            .foregroundColor(store.adaptiveTheme.primaryText)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                store.isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func permissionRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(store.bodyFont(size: 10.5))
                .foregroundColor(store.adaptiveTheme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            TactileSwitch(isOn: isOn, isDark: store.isDarkMode)
                .scaleEffect(0.85)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            store.isDarkMode ? Color.white.opacity(0.03) : Color.black.opacity(0.02),
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
    }

    @ViewBuilder
    private func extensionIcon(for id: String, size: CGFloat) -> some View {
        if let img = manager.icon(for: id) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                LeanIcon.extension.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.55, height: size * 0.55)
                    .foregroundColor(store.adaptiveTheme.secondaryText)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Single Extension Row in Popover List
@available(macOS 15.4, *)
private struct ExtensionPopoverRow: View {
    let item: BrowserExtensionManager.Installed
    @ObservedObject var store: LeanStore
    @ObservedObject var manager: BrowserExtensionManager
    let onSelectOptions: () -> Void

    @State private var isHovered = false
    @State private var isBreadcrumbHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Extension Icon
            if let icon = manager.icon(for: item.id) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    LeanIcon.extension.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                }
                .frame(width: 22, height: 22)
            }

            // Title and Subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(store.headingFont(size: 11.5))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                    .lineLimit(1)
                Text(item.fromStore == true ? "Chrome Web Store" : "Unpacked")
                    .font(store.bodyFont(size: 9.5))
                    .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // On/Off Tactile Switch
            TactileSwitch(
                isOn: Binding(
                    get: { item.enabled },
                    set: { manager.setEnabled(item.id, to: $0) }
                ),
                isDark: store.isDarkMode
            )
            .scaleEffect(0.9)

            // Breadcrumb / Options Button
            Button(action: onSelectOptions) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            isBreadcrumbHovered
                                ? (store.isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                : Color.clear
                        )
                    LeanIcon.dotsThree.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundColor(isBreadcrumbHovered ? store.adaptiveTheme.primaryText : store.adaptiveTheme.secondaryText)
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .onHover { isBreadcrumbHovered = $0 }
            .help("Extension options")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isHovered
                ? (store.isDarkMode ? Color.white.opacity(0.045) : Color.black.opacity(0.03))
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
