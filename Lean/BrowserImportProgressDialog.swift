import SwiftUI

enum BrowserImportStage: Equatable {
    case access, scanning, selection, importing, complete, failed

    var progressIndex: Int {
        switch self {
        case .access: 0
        case .scanning, .failed: 1
        case .selection: 2
        case .importing: 3
        case .complete: 4
        }
    }

    var isBusy: Bool {
        self == .scanning || self == .importing
    }
}

struct BrowserImportProgressDialog: View {
    let sourceTitle: String
    let isDark: Bool
    let uiFont: LeanFont
    @Binding var stage: BrowserImportStage
    @Binding var preview: BrowserImportPreview?
    @Binding var includeBookmarks: Bool
    @Binding var includeHistory: Bool
    @Binding var errorMessage: String?
    @Binding var resultMessage: String?
    let availableHistorySlots: Int
    let chooseFolder: () -> Void
    let importSelected: () -> Void
    let cancel: () -> Void

    private let labels = ["Access", "Scan", "Select", "Import"]
    private var ink: Color { isDark ? .white.opacity(0.9) : .black.opacity(0.85) }
    private var muted: Color { isDark ? .white.opacity(0.5) : .black.opacity(0.48) }
    private var accent: Color { isDark ? .white : .black.opacity(0.82) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import from \(sourceTitle)")
                .font(uiFont.font(size: 17, weight: .semibold))
                .foregroundColor(ink)

            progressIndicator
            Rectangle().fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)).frame(height: 1)
            stageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(20)
        .frame(width: 500, height: 410)
        .background(isDark ? Color(white: 0.10) : Color(white: 0.98))
        .interactiveDismissDisabled(stage.isBusy)
    }

    private var progressIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(index <= stage.progressIndex ? accent : muted.opacity(0.15))
                        Text(index < stage.progressIndex ? "✓" : "\(index + 1)")
                            .font(uiFont.font(size: 10, weight: .medium))
                            .foregroundColor(index <= stage.progressIndex ? (isDark ? .black : .white) : muted)
                    }
                    .frame(width: 21, height: 21)
                    Text(label)
                        .font(uiFont.font(size: 11, weight: index == stage.progressIndex ? .medium : .regular))
                        .foregroundColor(index <= stage.progressIndex ? ink : muted)
                }
                if index < labels.count - 1 {
                    Rectangle()
                        .fill(index < stage.progressIndex ? accent.opacity(0.7) : muted.opacity(0.18))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 7)
                }
            }
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .access:
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose the \(sourceTitle) data folder. Lean will find its profiles and read bookmarks and history without changing the browser's files.")
                    .font(uiFont.font(size: 12))
                    .foregroundColor(muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let errorMessage {
                    Text(errorMessage).font(uiFont.font(size: 11.5)).foregroundColor(.red)
                }
                SettingsActionButton("Choose browser folder", isDark: isDark, prominent: true, action: chooseFolder)
            }
        case .scanning:
            HStack(spacing: 10) {
                DotMatrixLoader(color: accent, size: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scanning browser profiles")
                        .font(uiFont.font(size: 12, weight: .medium)).foregroundColor(ink)
                    Text("Reading bookmarks and recent history…")
                        .font(uiFont.font(size: 11.5)).foregroundColor(muted)
                }
            }
        case .selection:
            if let preview {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose what to import")
                        .font(uiFont.font(size: 12.5, weight: .medium)).foregroundColor(ink)
                    CustomChecklistRow(
                        title: "Bookmarks (\(preview.bookmarks.count))",
                        isOn: $includeBookmarks,
                        isDark: isDark,
                        uiFont: uiFont
                    )
                    .disabled(preview.bookmarks.isEmpty)
                    CustomChecklistRow(
                        title: "History (\(preview.history.count) found, up to \(availableHistorySlots) can fit)",
                        isOn: $includeHistory,
                        isDark: isDark,
                        uiFont: uiFont
                    )
                    .disabled(preview.history.isEmpty)
                    Text("Passwords can be imported separately from a CSV export.")
                        .font(uiFont.font(size: 11)).foregroundColor(muted)
                        .padding(.top, 4)
                }
            } else {
                Text("No browser data is ready to import.").font(uiFont.font(size: 12)).foregroundColor(muted)
            }
        case .importing:
            HStack(spacing: 10) {
                DotMatrixLoader(color: accent, size: 16)
                Text("Importing the selected data…")
                    .font(uiFont.font(size: 12, weight: .medium)).foregroundColor(ink)
            }
        case .complete:
            VStack(alignment: .leading, spacing: 8) {
                Text("Import complete")
                    .font(uiFont.font(size: 13, weight: .medium)).foregroundColor(ink)
                Text(resultMessage ?? "Your selected browser data is in Lean.")
                    .font(uiFont.font(size: 12)).foregroundColor(muted)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 12) {
                Text("Lean couldn't read this browser folder.")
                    .font(uiFont.font(size: 12.5, weight: .medium)).foregroundColor(ink)
                Text(errorMessage ?? "Check the selected folder and try again.")
                    .font(uiFont.font(size: 11.5)).foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsActionButton("Choose another folder", isDark: isDark, action: chooseFolder)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            switch stage {
            case .selection:
                SettingsActionButton("Choose another folder", isDark: isDark, action: chooseFolder)
                Spacer()
                SettingsActionButton("Cancel", isDark: isDark, action: cancel)
                SettingsActionButton("Import selected", isDark: isDark, prominent: true, action: importSelected)
                    .disabled(!includeBookmarks && !includeHistory)
            case .complete:
                Spacer()
                SettingsActionButton("Done", isDark: isDark, prominent: true, action: cancel)
            case .access, .failed:
                Spacer()
                SettingsActionButton("Cancel", isDark: isDark, action: cancel)
            case .scanning, .importing:
                EmptyView()
            }
        }
    }
}
