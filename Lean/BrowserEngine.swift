import Foundation

/// Engine choice for the Lean shell.
///
/// The shell (LeanView / TopBar / Omnibar / Sidebar / Settings) never
/// touches an engine directly — it talks to `LeanTab`, which carries the
/// `engineKind` it was created with. Default is WebKit (zero bundled
/// binaries, tiny updates). CEF is opt-in per settings and applies to
/// newly opened tabs only; live tabs keep their engine so no view is
/// ever hot-swapped under the user.
enum BrowserEngineKind: String, Codable, CaseIterable, Identifiable {
    case webKit = "webKit"
    case cef = "cef"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webKit: return "WebKit"
        case .cef: return "Chromium (CEF)"
        }
    }

    var subtitle: String {
        switch self {
        case .webKit: return "System WebKit · default, no bundled engine"
        case .cef: return "Opt-in · new tabs only, requires bundled CEF"
        }
    }
}

/// Runtime probe + integration contract for the optional CEF engine.
///
/// CEF on macOS mandates a fixed app-bundle layout (the framework plus
/// GPU/renderer helper processes) and an ObjC++ bridge around
/// `CefBrowserView`. None of that ships with Lean today, so this enum only
/// answers "is the framework present?" Full bring-up steps live in
/// `docs/CEF.md`. The shell branches on this: CEF tabs render the normal
/// `WebView` only once a real `CEFEngineView` lands; until then they render
/// an in-content notice (shell chrome unchanged).
enum CEFIntegration {
    static let frameworkName = "Chromium Embedded Framework.framework"

    /// URL of the bundled CEF framework, if present.
    static func frameworkURL(bundle: Bundle = .main) -> URL? {
        if let url = bundle.url(
            forResource: "Chromium Embedded Framework",
            withExtension: "framework",
            subdirectory: "Frameworks"
        ) {
            return url
        }
        // Fallback for non-standard layouts / tests: check the frameworks path directly.
        let fallback = bundle.bundleURL
            .appendingPathComponent("Contents/Frameworks/\(frameworkName)", isDirectory: true)
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        return nil
    }

    /// True when the CEF framework is bundled and loadable.
    /// Pure over an injected predicate so it stays unit-testable.
    static func isAvailable(bundle: Bundle = .main) -> Bool {
        frameworkURL(bundle: bundle) != nil
    }

    /// True when running from an Xcode DerivedData build. The App Sandbox
    /// blocks the CEF helper's framework load there, so every renderer dies
    /// and pages stay blank. CEF requires an installed copy — see
    /// scripts/run-cef-dev.sh.
    static func isRunningFromDerivedData(bundle: Bundle = .main) -> Bool {
        bundle.bundleURL.path.contains("/DerivedData/")
    }

    /// True when a CEF tab can actually render in this process.
    static func canRender(bundle: Bundle = .main) -> Bool {
        isAvailable(bundle: bundle) && !isRunningFromDerivedData(bundle: bundle)
    }
}
