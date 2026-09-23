import Foundation
import WebKit

@available(macOS 15.4, *)
@MainActor
final class BrowserExtensionManager: NSObject, ObservableObject {
    struct Installed: Codable, Identifiable {
        let id: String
        var name: String
        var version: String
        var enabled: Bool
        var requiredPermissions: [String]
        var optionalPermissions: [String]
        var requiredHosts: [String]
        var optionalHosts: [String]
        var grantedPermissions: [String]
        var grantedHosts: [String]
        var fromStore: Bool?
    }

    struct InstallationReview: Identifiable {
        let id: String
        let name: String
        let version: String
        let requiredPermissions: [String]
        let optionalPermissions: [String]
        let requiredHosts: [String]
        let optionalHosts: [String]
        let warnings: [String]
        let fromStore: Bool
    }

    private struct PendingInstall {
        let review: InstallationReview
        let extensionModel: WKWebExtension
        let stagedFolder: URL
    }

    static let shared = BrowserExtensionManager()

    let controller = WKWebExtensionController()
    @Published private(set) var installed: [Installed] = []
    @Published private(set) var loadedIDs = Set<String>()
    @Published private(set) var errors: [String: [String]] = [:]
    @Published var errorMessage: String?
    @Published private(set) var isInstallingFromStore = false

    private var contexts: [String: WKWebExtensionContext] = [:]
    private var startupLoadTask: Task<Void, Never>?
    private var pending: [String: PendingInstall] = [:]
    private let directory = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true))
        .appendingPathComponent("Lean/Extensions", isDirectory: true)
    private var indexURL: URL { directory.appendingPathComponent("installed.json") }

    private override init() {
        super.init()
        controller.delegate = self
        if FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                installed = try JSONDecoder().decode([Installed].self, from: Data(contentsOf: indexURL))
            } catch {
                errorMessage = "Lean couldn't read its installed extensions list: \(error.localizedDescription)"
            }
        }
        startupLoadTask = Task {
            for item in installed where item.enabled { _ = await load(item.id) }
        }
    }

    func waitUntilReady() async { await startupLoadTask?.value }

    func prepareInstallation(from source: URL, installationID: String? = nil, fromStore: Bool = false) async -> InstallationReview? {
        errorMessage = nil
        let id = installationID ?? UUID().uuidString.lowercased()
        guard !installed.contains(where: { $0.id == id }), pending[id] == nil else {
            errorMessage = fromStore ? "That extension is already installed." : "That extension is already being installed."
            return nil
        }
        let staged = directory.appendingPathComponent(".staging-\(id)", isDirectory: true)
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }
        do {
            guard source.isFileURL,
                  FileManager.default.fileExists(atPath: source.appendingPathComponent("manifest.json").path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: staged)
            let extensionModel = try await WKWebExtension(resourceBaseURL: staged)
            let review = InstallationReview(
                id: id,
                name: extensionModel.displayName ?? source.lastPathComponent,
                version: extensionModel.version ?? "Unknown version",
                requiredPermissions: extensionModel.requestedPermissions.map(\.rawValue).sorted(),
                optionalPermissions: extensionModel.optionalPermissions.map(\.rawValue).sorted(),
                requiredHosts: extensionModel.allRequestedMatchPatterns.map(\.string).sorted(),
                optionalHosts: extensionModel.optionalPermissionMatchPatterns.map(\.string).sorted(),
                warnings: extensionModel.errors.map(\.localizedDescription),
                fromStore: fromStore
            )
            pending[id] = PendingInstall(review: review, extensionModel: extensionModel, stagedFolder: staged)
            return review
        } catch {
            try? FileManager.default.removeItem(at: staged)
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func cancelInstallation(_ review: InstallationReview) {
        guard let pendingInstall = pending.removeValue(forKey: review.id) else { return }
        try? FileManager.default.removeItem(at: pendingInstall.stagedFolder)
    }

    func install(_ review: InstallationReview, permissions: Set<String>, hosts: Set<String>) async {
        guard let pendingInstall = pending.removeValue(forKey: review.id) else { return }
        do {
            try FileManager.default.moveItem(at: pendingInstall.stagedFolder, to: folder(for: review.id))
            let item = Installed(
                id: review.id,
                name: review.name,
                version: review.version,
                enabled: true,
                requiredPermissions: review.requiredPermissions,
                optionalPermissions: review.optionalPermissions,
                requiredHosts: review.requiredHosts,
                optionalHosts: review.optionalHosts,
                grantedPermissions: permissions.union(review.requiredPermissions).sorted(),
                grantedHosts: hosts.union(review.requiredHosts).sorted(),
                fromStore: review.fromStore
            )
            installed.append(item)
            do { try save() } catch {
                installed.removeAll { $0.id == item.id }
                do {
                    try FileManager.default.moveItem(at: folder(for: item.id), to: pendingInstall.stagedFolder)
                } catch {
                    try? FileManager.default.removeItem(at: folder(for: item.id))
                }
                throw error
            }
            guard await load(item.id) else {
                errorMessage = "\(item.name) was added, but WebKit couldn't start it. See its diagnostics."
                return
            }
            errorMessage = nil
        } catch {
            try? FileManager.default.removeItem(at: pendingInstall.stagedFolder)
            errorMessage = error.localizedDescription
        }
    }

    func prepareStoreInstallation(from input: String) async -> InstallationReview? {
        errorMessage = nil
        guard let id = ChromeWebStoreInstaller.extensionID(from: input) else {
            errorMessage = ChromeWebStoreInstaller.InstallError.invalidAddress.localizedDescription
            return nil
        }
        guard !installed.contains(where: { $0.id == id }) else {
            errorMessage = ChromeWebStoreInstaller.InstallError.alreadyInstalled.localizedDescription
            return nil
        }

        isInstallingFromStore = true
        defer { isInstallingFromStore = false }
        let staged = directory.appendingPathComponent(".store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staged) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let package = try await ChromeWebStoreInstaller.fetch(id)
            try await Task.detached(priority: .userInitiated) {
                try ChromeWebStoreInstaller.unpack(package, expectedID: id, to: staged)
            }.value
            return await prepareInstallation(from: staged, installationID: id, fromStore: true)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func setEnabled(_ id: String, to enabled: Bool) {
        guard let index = installed.firstIndex(where: { $0.id == id }), installed[index].enabled != enabled else { return }
        installed[index].enabled = enabled
        do { try save() } catch { errorMessage = error.localizedDescription }
        if enabled {
            Task { await load(id) }
        } else {
            unload(id)
        }
    }

    func reload(_ id: String) {
        guard installed.contains(where: { $0.id == id }) else { return }
        Task {
            unload(id)
            guard await load(id) else {
                errorMessage = "The extension couldn't be reloaded. See its diagnostics."
                return
            }
            errorMessage = nil
        }
    }

    func remove(_ id: String) {
        unload(id)
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        let removed = installed.remove(at: index)
        do {
            try save()
        } catch {
            installed.insert(removed, at: index)
            errorMessage = error.localizedDescription
            return
        }
        do {
            try FileManager.default.removeItem(at: folder(for: id))
            errors[id] = nil
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            errors[id] = nil
        } catch {
            installed.insert(removed, at: index)
            do { try save() } catch { errorMessage = error.localizedDescription }
            if removed.enabled { Task { await load(id) } }
            errorMessage = "Couldn't remove the extension files: \(error.localizedDescription)"
        }
    }

    func setPermission(_ permission: String, enabled: Bool, for id: String) {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[index].grantedPermissions = updated(installed[index].grantedPermissions, value: permission, enabled: enabled)
        if let context = contexts[id],
           let requested = context.webExtension.requestedPermissions.union(context.webExtension.optionalPermissions)
            .first(where: { $0.rawValue == permission }) {
            context.setPermissionStatus(enabled ? .grantedExplicitly : .deniedExplicitly, for: requested)
        }
        do { try save() } catch { errorMessage = error.localizedDescription }
    }

    func setHost(_ host: String, enabled: Bool, for id: String) {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[index].grantedHosts = updated(installed[index].grantedHosts, value: host, enabled: enabled)
        if let context = contexts[id],
           let pattern = context.webExtension.allRequestedMatchPatterns.union(context.webExtension.optionalPermissionMatchPatterns)
            .first(where: { $0.string == host }) {
            context.setPermissionStatus(enabled ? .grantedExplicitly : .deniedExplicitly, for: pattern)
        }
        do { try save() } catch { errorMessage = error.localizedDescription }
    }

    private func load(_ id: String) async -> Bool {
        guard let index = installed.firstIndex(where: { $0.id == id }), installed[index].enabled else { return false }
        do {
            let extensionModel = try await WKWebExtension(resourceBaseURL: folder(for: id))
            let context = WKWebExtensionContext(for: extensionModel)
            context.uniqueIdentifier = id
            for permission in extensionModel.requestedPermissions.union(extensionModel.optionalPermissions) {
                let granted = installed[index].grantedPermissions.contains(permission.rawValue)
                context.setPermissionStatus(granted ? .grantedExplicitly : .deniedExplicitly, for: permission)
            }
            for pattern in extensionModel.allRequestedMatchPatterns.union(extensionModel.optionalPermissionMatchPatterns) {
                let granted = installed[index].grantedHosts.contains(pattern.string)
                context.setPermissionStatus(granted ? .grantedExplicitly : .deniedExplicitly, for: pattern)
            }
            try controller.load(context)
            contexts[id] = context
            loadedIDs.insert(id)
            errors[id] = context.errors.map(\.localizedDescription)
            return true
        } catch {
            loadedIDs.remove(id)
            errors[id] = [error.localizedDescription]
            return false
        }
    }

    private func unload(_ id: String) {
        guard let context = contexts.removeValue(forKey: id) else { return }
        do {
            try controller.unload(context)
            loadedIDs.remove(id)
        } catch {
            errors[id] = [error.localizedDescription]
        }
    }

    private func updated(_ values: [String], value: String, enabled: Bool) -> [String] {
        enabled ? Array(Set(values).union([value])).sorted() : values.filter { $0 != value }
    }

    private func folder(for id: String) -> URL {
        directory.appendingPathComponent(id, isDirectory: true)
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(installed).write(to: indexURL, options: .atomic)
    }
}

@available(macOS 15.4, *)
extension BrowserExtensionManager: WKWebExtensionControllerDelegate { }
