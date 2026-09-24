import SwiftUI

// Walking a user through every extension found in another browser, one
// permission review at a time. It reuses the exact review sheet the
// Extensions settings use — an import never grants anything silently —
// advancing on install, skipping on cancel or on an extension WebKit
// can't read, and reporting both piles at the end.
@available(macOS 15.4, *)
@MainActor
final class ExtensionImportReviewer: ObservableObject {
    @Published var pendingReview: BrowserExtensionManager.InstallationReview?
    var onQueueDrained: ((String) -> Void)?

    private let manager = BrowserExtensionManager.shared
    private var queue: [FoundExtension] = []
    private var installedNames: [String] = []
    private var skipped: [(name: String, reason: String)] = []
    private var alreadyInstalled = 0

    func start(_ extensions: [FoundExtension]) {
        queue = extensions.filter { found in
            !manager.installed.contains(where: { $0.id == found.id })
        }
        alreadyInstalled = extensions.count - queue.count
        installedNames = []
        skipped = []
        advance()
        if queue.isEmpty && pendingReview == nil { drain() }
    }

    func cancelCurrent() {
        if let review = pendingReview {
            manager.cancelInstallation(review)
            skipped.append((review.name, "skipped"))
        }
        pendingReview = nil
        advance()
        if queue.isEmpty && pendingReview == nil { drain() }
    }

    func installCurrent(permissions: Set<String>, hosts: Set<String>) async {
        guard let review = pendingReview else { return }
        await manager.install(review, permissions: permissions, hosts: hosts)
        if manager.installed.contains(where: { $0.id == review.id }) {
            installedNames.append(review.name)
        } else {
            skipped.append((review.name, manager.errorMessage ?? "couldn't install"))
        }
        pendingReview = nil
        advance()
        if queue.isEmpty && pendingReview == nil { drain() }
    }

    private func advance() {
        guard pendingReview == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        Task { @MainActor in
            let didAccess = next.path.startAccessingSecurityScopedResource()
            defer { if didAccess { next.path.stopAccessingSecurityScopedResource() } }
            if let review = await manager.prepareInstallation(from: next.path, installationID: next.id) {
                pendingReview = review
            } else {
                skipped.append((next.name, manager.errorMessage ?? "couldn't read"))
                advance()
                if queue.isEmpty && pendingReview == nil { drain() }
            }
        }
    }

    private func drain() {
        var parts: [String] = []
        if !installedNames.isEmpty {
            parts.append("\(installedNames.count) extensions installed (\(installedNames.prefix(3).joined(separator: ", "))\(installedNames.count > 3 ? "…" : ""))")
        }
        if alreadyInstalled > 0 {
            parts.append("\(alreadyInstalled) already in Lean")
        }
        for entry in skipped {
            parts.append("\(entry.name): \(entry.reason)")
        }
        onQueueDrained?(parts.joined(separator: "; "))
    }
}

// The invisible host that owns the reviewer (the import section itself
// can't: it isn't availability-gated, and neither are the dialog or the
// scan states). The section drops in an import request; the host runs the
// queue and hands back one summary line.
@available(macOS 15.4, *)
struct ExtensionImportReviewHost: View {
    @Binding var request: [FoundExtension]?
    @Binding var result: String?
    let isDark: Bool
    let uiFont: LeanFont

    @StateObject private var reviewer = ExtensionImportReviewer()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: request) { _, next in
                guard let next else { return }
                reviewer.onQueueDrained = { line in
                    result = line.isEmpty ? nil : line
                    request = nil
                }
                reviewer.start(next)
            }
            .sheet(item: $reviewer.pendingReview) { review in
                ExtensionInstallReviewSheet(review: review, isDark: isDark, uiFont: uiFont) {
                    reviewer.cancelCurrent()
                } install: { permissions, hosts in
                    await reviewer.installCurrent(permissions: permissions, hosts: hosts)
                }
                .interactiveDismissDisabled()
            }
    }
}
