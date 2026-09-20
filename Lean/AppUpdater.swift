import AppKit
import Sparkle

/// Sparkle in-app updater.
///
/// Updates come from per-architecture appcasts published as GitHub Release
/// assets. Archives are authenticated with the Ed25519 key in Info.plist
/// (`SUPublicEDKey`) — that signature is what makes updates safe on an
/// ad-hoc signed, unnotarized app.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        #if DEBUG
        controller.updater.automaticallyChecksForUpdates = false
        #endif
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    var currentVersion: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (short?, build?):
            return "\(short) (\(build))"
        case let (short?, nil):
            return short
        default:
            return "Unknown"
        }
    }

    // MARK: - SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        #error("Unsupported architecture for Sparkle updates")
        #endif
        return "https://github.com/DeepanshuMishraa/lean/releases/latest/download/appcast-\(arch).xml"
    }
}
