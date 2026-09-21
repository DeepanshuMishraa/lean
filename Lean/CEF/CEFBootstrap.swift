import AppKit
import Foundation

/// One-time CEF startup. Idempotent; safe to call from any tab creation.
/// Never initializes under XCTest (isolated stores must not spawn helpers).
/// Returns false when CEF is unavailable — callers fall back to WebKit UI.
enum CEFBootstrap {
    private static var didAttempt = false
    private static var ready = false

    static func ensureInitialized() -> Bool {
        if didAttempt { return ready }
        didAttempt = true
        guard CEFIntegration.isAvailable(),
              CEFManager.isSupported(),
              NSClassFromString("XCTestCase") == nil,
              let frameworkURL = CEFIntegration.frameworkURL()
        else { return false }

        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first
        else { return false }
        let cacheURL = appSupport.appendingPathComponent("Lean/CEF", isDirectory: true)
        try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let logURL = cacheURL.appendingPathComponent("cef.log")

        let frameworksURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks", isDirectory: true)
        let helperURL = frameworksURL
            .appendingPathComponent("Lean Helper.app/Contents/MacOS/Lean Helper")
        let resourcesURL = frameworkURL
            .appendingPathComponent("Resources", isDirectory: true)

        do {
            try CEFManager.initialize(withCachePath: cacheURL.path,
                                      subprocessPath: helperURL.path,
                                      resourcesPath: resourcesURL.path,
                                      mainBundlePath: Bundle.main.bundlePath,
                                      logPath: logURL.path)
            ready = true
            CEFManager.startMessagePump()
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { _ in CEFManager.stopMessagePump() }
            NSLog("CEF initialized: %@", CEFManager.cefVersion())
        } catch {
            NSLog("CEF bootstrap failed: %@", String(describing: error))
        }
        return ready
    }
}
