import Foundation

enum PageScripts {
    static let pageReadyMessageName = "pageReady"

    static let pageReady = """
    document.addEventListener('DOMContentLoaded', function() {
        requestAnimationFrame(function() {
            requestAnimationFrame(function() {
                window.webkit.messageHandlers.\(pageReadyMessageName).postMessage(location.href);
            });
        });
    }, { once: true });
    """

    static func font(_ font: LeanFont) -> String {
        if font == .system {
            return "document.getElementById('lean-custom-font-style')?.remove();"
        }

        let css = """
        html body, html body *:not(svg):not(svg *) { font-family: \(font.cssFamily) !important; }
        """.replacingOccurrences(of: "\n", with: " ")

        return """
        (function() {
            var style = document.getElementById('lean-custom-font-style');
            if (!style) {
                style = document.createElement('style');
                style.id = 'lean-custom-font-style';
                (document.head || document.documentElement).appendChild(style);
            }
            style.textContent = "\(css)";
        })();
        """
    }

    static func scrollbar(_ style: ScrollbarStyle) -> String {
        let css: String
        switch style {
        case .hidden:
            css = """
            ::-webkit-scrollbar { display: none !important; width: 0px !important; height: 0px !important; }
            html, body { -ms-overflow-style: none !important; scrollbar-width: none !important; }
            """
        case .thin:
            css = """
            ::-webkit-scrollbar { width: 4px !important; height: 4px !important; }
            ::-webkit-scrollbar-track { background: transparent !important; }
            ::-webkit-scrollbar-thumb { background: rgba(128, 128, 128, 0.4) !important; border-radius: 4px !important; }
            ::-webkit-scrollbar-thumb:hover { background: rgba(128, 128, 128, 0.7) !important; }
            html, body { scrollbar-width: thin !important; }
            """
        case .normal:
            css = """
            ::-webkit-scrollbar { width: auto !important; height: auto !important; }
            ::-webkit-scrollbar-track { background: auto !important; }
            ::-webkit-scrollbar-thumb { background: auto !important; }
            html, body { scrollbar-width: auto !important; }
            """
        }

        let escapedCSS = css.replacingOccurrences(of: "\n", with: " ")
        return """
        (function() {
            function inject() {
                var existing = document.getElementById('lean-custom-scrollbar-style');
                if (!existing) {
                    existing = document.createElement('style');
                    existing.id = 'lean-custom-scrollbar-style';
                    var target = document.head || document.documentElement;
                    if (target) {
                        target.appendChild(existing);
                    }
                }
                if (existing) {
                    existing.textContent = "\(escapedCSS)";
                }
            }
            inject();
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', inject, { once: true });
            }
        })();
        """
    }

    static func smoothScrolling(enabled: Bool) -> String {
        let css = enabled ? "html { scroll-behavior: smooth !important; }" : ""
        return """
        (function() {
            function apply() {
                var style = document.getElementById('lean-native-smooth-scroll-style');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'lean-native-smooth-scroll-style';
                    (document.head || document.documentElement).appendChild(style);
                }
                style.textContent = "\(css)";
            }
            apply();
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', apply, { once: true });
            }
        })();
        """
    }
}
