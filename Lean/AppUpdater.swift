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
    /// Release channel shown in the UI. The app is pre-1.0.
    static let releaseChannel = "Alpha"

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

    var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    var currentVersion: String {
        "\(marketingVersion) (\(buildVersion))"
    }

    // MARK: - SPUUpdaterDelegate

    /// Surfaces the real failure instead of Sparkle's generic Cancel-only
    /// alert: domain, code, and underlying errors go to the log (diagnosable
    /// from Console) and the alert carries the message.
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        NSLog(
            "Lean update aborted: %@ (%@ %d) underlying: %@",
            nsError.localizedDescription,
            nsError.domain,
            nsError.code,
            String(describing: nsError.userInfo[NSUnderlyingErrorKey])
        )
    }

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
