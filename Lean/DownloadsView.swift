import PhosphorSwift
import SwiftUI

// MARK: - Bespoke Downloads Popover (same card language as Quick Settings)
struct DownloadsPopover: View {
    @ObservedObject var store: LeanStore
    @State private var isFooterHovered = false
    @State private var isClearHovered = false

    private var downloads: [DownloadItem] {
        store.downloadManager.downloads
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Text("Downloads")
                    .font(store.headingFont(size: 12.5))
                    .foregroundColor(store.adaptiveTheme.primaryText)

                if store.downloadManager.hasActiveDownloads {
                    Text("\(store.downloadManager.activeDownloads.count) active")
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

                if downloads.contains(where: { !$0.isActive }) {
                    Button {
                        withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                            store.downloadManager.clearCompleted()
                        }
                    } label: {
                        Text("Clear")
                            .font(store.bodyFont(size: 11))
                            .foregroundColor(isClearHovered ? store.adaptiveTheme.primaryText : store.adaptiveTheme.secondaryText)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(
                                isClearHovered
                                    ? (store.isDarkMode ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { isClearHovered = $0 }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)

            if downloads.isEmpty {
                VStack(spacing: 8) {
                    Ph.arrowCircleDown.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundColor(store.adaptiveTheme.secondaryText.opacity(0.7))
                    Text("No downloads yet")
                        .font(store.headingFont(size: 12))
                        .foregroundColor(store.adaptiveTheme.primaryText)
                    Text("Files you download will appear here with live progress.")
                        .font(store.bodyFont(size: 11))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(downloads.prefix(12)) { item in
                            DownloadPopoverRow(item: item, store: store)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Rectangle()
                .fill(store.themeColors.divider)
                .frame(height: 0.75)
                .padding(.vertical, 2)

            // Footer → full Downloads settings
            Button {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                    store.isDownloadsPresented = false
                }
                store.openSettings(category: .downloads)
            } label: {
                HStack(spacing: 8) {
                    Ph.arrowCircleDown.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                    Text("Show All Downloads...")
                        .font(store.headingFont(size: 12))
                    Spacer()
                    Ph.caretRight.fill
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
        .padding(8)
        .frame(width: 300)
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
                        store.downloadsPopoverFrame = proxy.frame(in: .global)
                    }
                    .onChange(of: proxy.frame(in: .global)) { _, newFrame in
                        store.downloadsPopoverFrame = newFrame
                    }
            }
        )
        .onDisappear {
            store.downloadsPopoverFrame = .zero
        }
    }
}

// MARK: - Single download row
private struct DownloadPopoverRow: View {
    let item: DownloadItem
    @ObservedObject var store: LeanStore
    @State private var isHovered = false
    @State private var showHoverActions = false
    @State private var hoverWorkItem: DispatchWorkItem?

    /// Hover actions fade in after a short delay so the second click of a
    /// double-click can't land on a button that just popped into layout
    /// (notably Cancel on an active download).
    private func setHovered(_ hovering: Bool) {
        isHovered = hovering
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        if hovering {
            let work = DispatchWorkItem { showHoverActions = true }
            hoverWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        } else {
            showHoverActions = false
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            DownloadFormat.icon(for: item.fileName).fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 13, height: 13)
                .foregroundColor(store.adaptiveTheme.secondaryText)
                .frame(width: 22, height: 22)
                .background(
                    store.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(store.headingFont(size: 12))
                    .foregroundColor(store.adaptiveTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if item.state == .downloading {
                    // Thin live progress track
                    GeometryReader { geo in
                        Capsule()
                            .fill(store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                            .frame(height: 3)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(store.isDarkMode ? Color.white.opacity(0.85) : Color.black.opacity(0.75))
                                    .frame(width: geo.size.width * CGFloat(item.fractionCompleted), height: 3)
                            }
                    }
                    .frame(height: 3)

                    Text(downloadingSubtitle)
                        .font(store.bodyFont(size: 10.5))
                        .foregroundColor(store.adaptiveTheme.secondaryText)
                        .lineLimit(1)
                } else {
                    Text(finishedSubtitle)
                        .font(store.bodyFont(size: 10.5))
                        .foregroundColor(
                            item.state == .failed
                                ? Color.red.opacity(0.85)
                                : store.adaptiveTheme.secondaryText
                        )
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if item.state == .downloading {
                    // % stays put; Cancel fades in beside it without shifting layout.
                    if item.totalBytes > 0 {
                        Text("\(Int((item.fractionCompleted * 100).rounded()))%")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(store.adaptiveTheme.secondaryText)
                    }
                    HoverIconButton(
                        icon: .x,
                        help: "Cancel download",
                        store: store
                    ) {
                        store.cancelDownload(id: item.id)
                    }
                    .opacity(showHoverActions ? 1 : 0)
                    .disabled(!showHoverActions)
                } else if showHoverActions {
                    HoverIconButton(
                        icon: .folder,
                        help: "Show in Finder",
                        store: store
                    ) {
                        store.revealDownload(item)
                    }
                    if item.state == .completed {
                        HoverIconButton(
                            icon: .arrowUpRight,
                            help: "Open file",
                            store: store
                        ) {
                            store.openDownload(item)
                        }
                    }
                    HoverIconButton(
                        icon: .trash,
                        help: "Remove from list",
                        store: store
                    ) {
                        withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
                            store.downloadManager.removeDownload(id: item.id)
                        }
                    }
                }
            }
            .frame(minWidth: 50, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isHovered
                ? (store.isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover(perform: setHovered)
        .help(item.destinationURL.path)
        .onTapGesture {
            if item.state == .completed {
                store.openDownload(item)
            } else {
                store.revealDownload(item)
            }
        }
        .onDisappear {
            hoverWorkItem?.cancel()
            hoverWorkItem = nil
        }
    }

    private var downloadingSubtitle: String {
        var parts: [String] = [DownloadFormat.progressText(received: item.receivedBytes, total: item.totalBytes)]
        let speed = DownloadFormat.speed(item.speedBytesPerSec)
        if speed != "—" {
            parts.append(speed)
        }
        return parts.joined(separator: " · ")
    }

    private var finishedSubtitle: String {
        switch item.state {
        case .completed:
            let when = item.endDate.map { DownloadFormat.relativeTime($0) } ?? "just now"
            let size = item.totalBytes > 0 ? DownloadFormat.fileSize(item.totalBytes) : DownloadFormat.fileSize(item.receivedBytes)
            return "Done · \(when) · \(size)"
        case .failed:
            if let desc = item.errorDescription, !desc.isEmpty, desc != "Interrupted by relaunch" {
                return "Failed · \(desc)"
            }
            return "Failed · \(DownloadFormat.relativeTime(item.endDate ?? item.startDate))"
        case .cancelled:
            return "Cancelled"
        case .downloading:
            return ""
        }
    }
}

private struct HoverIconButton: View {
    let icon: Ph
    let help: String
    @ObservedObject var store: LeanStore
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            icon.uiIcon
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
                .foregroundColor(
                    isHovered ? store.adaptiveTheme.primaryText : store.adaptiveTheme.secondaryText
                )
                .frame(width: 24, height: 24)
                .background(
                    isHovered
                        ? (store.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(help)
        .onHover { isHovered = $0 }
    }
}
