import Foundation

enum PageScripts {
    static let pageReadyMessageName = "pageReady"

    static let pageReady = """
    (function() {
        var notified = false;
        function notify() {
            if (notified) return;
            notified = true;
            try {
                window.webkit.messageHandlers.\(pageReadyMessageName).postMessage(location.href);
            } catch(e) {}
        }

        try {
            var po = new PerformanceObserver(function(list) {
                var entries = list.getEntries();
                for (var i = 0; i < entries.length; i++) {
                    if (entries[i].name === 'first-contentful-paint' || entries[i].name === 'first-paint') {
                        notify();
                        po.disconnect();
                        return;
                    }
                }
            });
            po.observe({ type: 'paint', buffered: true });
        } catch(e) {}

        try {
            var mo = new MutationObserver(function() {
                if (document.body && (document.body.children.length > 0 || (document.body.innerText && document.body.innerText.trim().length > 0))) {
                    notify();
                    mo.disconnect();
                }
            });
            if (document.documentElement) {
                mo.observe(document.documentElement, { childList: true, subtree: true });
            }
        } catch(e) {}

        if (document.readyState === 'interactive' || document.readyState === 'complete') {
            notify();
        }

        document.addEventListener('DOMContentLoaded', function() {
            requestAnimationFrame(function() {
                requestAnimationFrame(function() {
                    notify();
                });
            });
        }, { once: true });
    })();
    """

    static func font(_ font: LeanFont, headingWeight: Int = 0, bodyWeight: Int = 0) -> String {
        var rules: [String] = []

        if font != .system {
            rules.append("html body, html body *:not(svg):not(svg *) { font-family: \(font.cssFamily) !important; }")
        }

        if headingWeight > 0 {
            rules.append("h1, h2, h3, h4, h5, h6, [role=\"heading\"], .heading, .title { font-weight: \(headingWeight) !important; }")
        }

        if bodyWeight > 0 {
            rules.append("body, p, li, span, a, label, input, textarea, blockquote, dd, dt { font-weight: \(bodyWeight) !important; }")
        }

        if rules.isEmpty {
            return "document.getElementById('lean-custom-font-style')?.remove();"
        }

        let css = rules.joined(separator: " ").replacingOccurrences(of: "\n", with: " ")

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

    static func smoothScrolling(enabled: Bool) -> String {        let css = enabled ? "html { scroll-behavior: smooth !important; }" : ""
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
