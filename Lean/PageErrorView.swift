import SwiftUI

// A failed navigation, worth a page: what broke, where, and how to get back.
// Renders directly on the page canvas (no floating nested cards or heavy borders),
// providing a calm, minimal, native browser error page.

struct PageErrorView: View {
    @ObservedObject var store: LeanStore
    @ObservedObject var tab: LeanTab
    let error: PageLoadError

    @State private var isDetailsExpanded = false
    @State private var hasCopiedDiagnostics = false
    @State private var hasCopiedUrl = false
    @State private var isReloading = false
    @State private var appeared = false

    private var pageBackground: Color {
        store.adaptiveTheme.activeTabBackground
    }

    private var iconTint: Color {
        if error.kind == .insecure {
            return Color(red: 235/255, green: 130/255, blue: 30/255)
        }
        return store.adaptiveTheme.primaryText.opacity(0.75)
    }

    var body: some View {
        ZStack {
            // Native page background
            pageBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                VStack(alignment: .leading, spacing: 20) {
                    // Header line: Category icon, badge name, and technical code
                    HStack(spacing: 9) {
                        error.kind.icon.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 17, height: 17)
                            .foregroundColor(iconTint)

                        Text(error.kind.badgeText.uppercased())
                            .font(store.leanUIFont.font(size: 10, weight: .bold))
                            .tracking(0.7)
                            .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.85))

                        Text("·")
                            .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.35))

                        Text(error.kind.errorCodeString)
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.55))

                        Spacer()
                    }

                    // Main Title
                    Text(error.title)
                        .font(store.headingFont(size: 24, weight: .semibold))
                        .foregroundColor(store.adaptiveTheme.primaryText)
                        .tracking(-0.3)

                    // URL if available
                    if let url = error.url {
                        HStack(spacing: 6) {
                            Text(url.absoluteString)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.9))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button(action: copyURL) {
                                (hasCopiedUrl ? LeanIcon.check.bold : LeanIcon.copy.fill)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 10, height: 10)
                                    .foregroundColor(hasCopiedUrl ? Color.green : store.adaptiveTheme.secondaryText.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .help(hasCopiedUrl ? "Copied!" : "Copy address")
                        }
                    }

                    // Error Message Description
                    Text(error.message)
                        .font(store.leanUIFont.font(size: 13.5))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    // Local Dev Server Note
                    if error.isDevServer {
                        HStack(alignment: .top, spacing: 8) {
                            LeanIcon.code.fill
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 13, height: 13)
                                .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.7))
                                .padding(.top, 2)

                            Text("Check your terminal to verify that your local development server is running and listening on this port.")
                                .font(store.leanUIFont.font(size: 12))
                                .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.85))
                                .lineSpacing(3)
                        }
                        .padding(.top, 2)
                    }

                    // Action buttons
                    HStack(spacing: 9) {
                        Button(action: reload) {
                            HStack(spacing: 6) {
                                LeanIcon.arrowClockwise.bold
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 11, height: 11)
                                    .rotationEffect(.degrees(isReloading ? 360 : 0))
                                    .animation(
                                        isReloading
                                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                            : .default,
                                        value: isReloading
                                    )

                                Text("Try Again")
                                    .font(store.leanUIFont.font(size: 12, weight: .semibold))

                                Text("⌘R")
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                    .opacity(0.6)
                            }
                            .foregroundColor(store.isDarkMode ? Color.black : Color.white)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(store.isDarkMode ? Color.white : Color.black)
                            )
                        }
                        .buttonStyle(.plain)

                        if tab.canGoBack {
                            Button(action: { pageErrorClearing { tab.goBack() } }) {
                                HStack(spacing: 5) {
                                    LeanIcon.arrowLeft.bold
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 10, height: 10)

                                    Text("Go Back")
                                        .font(store.leanUIFont.font(size: 12, weight: .medium))

                                    Text("⌘[")
                                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                        .opacity(0.6)
                                }
                                .foregroundColor(store.adaptiveTheme.primaryText)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(store.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: openOmnibarForEditing) {
                            HStack(spacing: 5) {
                                LeanIcon.magnifyingGlass.fill
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 10.5, height: 10.5)

                                Text("Search")
                                    .font(store.leanUIFont.font(size: 12, weight: .medium))
                            }
                            .foregroundColor(store.adaptiveTheme.secondaryText)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(store.isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Search the web or enter a new address")
                    }
                    .padding(.top, 6)

                    // Technical Details Disclosure
                    technicalDetailsSection
                        .padding(.top, 6)
                }
                .frame(maxWidth: 500, alignment: .leading)
                .padding(.horizontal, 36)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)

                Spacer(minLength: 60)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.20)) {
                appeared = true
            }
        }
    }

    // MARK: - Technical Details
    private var technicalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                    isDetailsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    (isDetailsExpanded ? LeanIcon.caretDown.bold : LeanIcon.caretRight.bold)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 8, height: 8)
                        .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.65))

                    Text(isDetailsExpanded ? "Hide Technical Details" : "Show Technical Details")
                        .font(store.leanUIFont.font(size: 11.5, weight: .medium))
                        .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.75))
                }
            }
            .buttonStyle(.plain)

            if isDetailsExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    diagnosticRow(label: "Error Code", value: "\(error.errorCode ?? -1)")
                    if let domain = error.errorDomain {
                        diagnosticRow(label: "Domain", value: domain)
                    }
                    if let desc = error.localizedDescription {
                        diagnosticRow(label: "Description", value: desc)
                    }
                    if let url = error.url {
                        diagnosticRow(label: "URL", value: url.absoluteString)
                    }

                    HStack {
                        Button(action: copyDiagnostics) {
                            HStack(spacing: 4) {
                                (hasCopiedDiagnostics ? LeanIcon.check.bold : LeanIcon.copy.fill)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 9.5, height: 9.5)
                                    .foregroundColor(hasCopiedDiagnostics ? Color.green : store.adaptiveTheme.secondaryText)

                                Text(hasCopiedDiagnostics ? "Copied" : "Copy Diagnostics")
                                    .font(store.leanUIFont.font(size: 10.5, weight: .medium))
                                    .foregroundColor(hasCopiedDiagnostics ? Color.green : store.adaptiveTheme.secondaryText)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
            }
        }
    }

    private func diagnosticRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.65))
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundColor(store.adaptiveTheme.primaryText.opacity(0.85))
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }

    // MARK: - Actions
    private func reload() {
        isReloading = true
        tab.pageError = nil
        if let url = error.url {
            tab.load(url)
        } else {
            tab.reload()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isReloading = false
        }
    }

    private func pageErrorClearing(_ action: () -> Void) {
        tab.pageError = nil
        action()
    }

    private func openOmnibarForEditing() {
        store.showFloatingOmnibar(mode: .newTab)
    }

    private func copyURL() {
        guard let url = error.url?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)

        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            hasCopiedUrl = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.16)) {
                hasCopiedUrl = false
            }
        }
    }

    private func copyDiagnostics() {
        var lines: [String] = []
        lines.append("Title: \(error.title)")
        lines.append("Code: \(error.errorCode ?? -1)")
        if let domain = error.errorDomain { lines.append("Domain: \(domain)") }
        if let desc = error.localizedDescription { lines.append("Description: \(desc)") }
        if let url = error.url { lines.append("URL: \(url.absoluteString)") }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)

        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            hasCopiedDiagnostics = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.16)) {
                hasCopiedDiagnostics = false
            }
        }
    }
}
