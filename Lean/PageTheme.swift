import AppKit
import SwiftUI
import WebKit

/// Recolours web pages to the browser's colour theme with Dark Reader's
/// engine (MIT, vendored as `darkreader.js`). It rewrites the page's own
/// colours, stylesheet rule by rule, so hover states, shadow DOM, images and
/// single-page apps keep working, and every surface takes the theme's
/// background and text colour rather than a generic dark or light.
///
/// The engine runs in Lean's content world: the page cannot see it and the
/// globals it sets stay out of the page's reach.
struct PageTheme: Equatable {
    /// Whether the target is the dark variant of the theme.
    let isDark: Bool
    /// `#rrggbb`.
    let background: String
    /// `#rrggbb`.
    let text: String

    init?(background: Color, text: Color, isDark: Bool) {
        guard let background = Self.hex(background), let text = Self.hex(text) else { return nil }
        self.isDark = isDark
        self.background = background
        self.text = text
    }

    private static func hex(_ color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func byte(_ value: CGFloat) -> Int { Int((value * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }
}

extension PageScripts {
    static let themeFetchMessageName = "leanThemeFetch"

    private static let darkReaderSource: String = {
        guard let url = Bundle.main.url(forResource: "darkreader", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()

    /// The engine plus its settings, or nil when there is no theme or the
    /// engine file is missing from the bundle.
    static func pageThemeSource(_ theme: PageTheme?) -> String? {
        guard let theme, !darkReaderSource.isEmpty else { return nil }
        return darkReaderSource + "\n" + """
        (function() {
            if (location.protocol !== 'http:' && location.protocol !== 'https:') return;
            var DR = globalThis.DarkReader;
            if (!DR) return;

            // Stylesheets from other origins can't be read by the page. Try
            // the page's own fetch, then ask Lean to download the file.
            DR.setFetchMethod(function(url) {
                return fetch(url, { credentials: 'omit' }).catch(function() {
                    return window.webkit.messageHandlers.\(themeFetchMessageName).postMessage(String(url)).then(function(reply) {
                        var binary = atob(reply.base64);
                        var bytes = new Uint8Array(binary.length);
                        for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
                        return new Response(bytes, { status: 200, headers: { 'Content-Type': reply.type || '' } });
                    });
                });
            });

            DR.enable({
                mode: \(theme.isDark ? 1 : 0),
                brightness: 100,
                contrast: 100,
                sepia: 0,
                grayscale: 0,
                darkSchemeBackgroundColor: '\(theme.background)',
                darkSchemeTextColor: '\(theme.text)',
                lightSchemeBackgroundColor: '\(theme.background)',
                lightSchemeTextColor: '\(theme.text)'
            });
        })();
        """
    }

    /// Takes the theme off a loaded page.
    static let pageThemeOff = "(function(){ var DR = globalThis.DarkReader; if (DR) DR.disable(); })();"
}

/// Downloads a file for the theme engine when the page itself may not
/// (cross-origin CSS and images). Lives in Lean's content world, so page
/// scripts cannot call it. Only http(s), no cookies, size-capped.
final class PageThemeFetch: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = PageThemeFetch()
    private static let maxBytes = 10_000_000

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard let string = message.body as? String,
              let url = URL(string: string),
              url.scheme == "http" || url.scheme == "https"
        else { return (nil, "Not an http(s) URL.") }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard data.count <= Self.maxBytes else { return (nil, "File is larger than 10 MB.") }
            let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
            return (["base64": data.base64EncodedString(), "type": type], nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}
