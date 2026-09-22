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

    /// YouTube in-player ads. Same-origin creatives can't be blocked at the
    /// network layer without breaking playback, so this prunes the ad
    /// schedule out of `youtubei/v1/player` + `/next` responses before the
    /// player ever sees it (no ad mode, no flash, no spinner): `fetch` is
    /// wrapped for those endpoints and `JSON.parse` is wrapped for XHR
    /// flows. A skip/mute fallback covers anything that still slips into
    /// ad mode. Hostname-guarded; inert everywhere else. Document-start so
    /// the patches win the race with the player bootstrap.
    static func youtubeAds(enabled: Bool) -> String {
        if !enabled {
            return "void 0;"
        }
        return """
        (function() {
            try {
                var host = location.hostname || '';
                if (!/(^|\\.)youtube\\.com$|(^|\\.)youtu\\.be$/.test(host)) return;
            } catch (e) { return; }

            function stripAds(obj) {
                if (!obj || typeof obj !== 'object') return;
                var keys = ['adPlacements', 'playerAds', 'adSlots'];
                for (var i = 0; i < keys.length; i++) {
                    try {
                        if (Object.prototype.hasOwnProperty.call(obj, keys[i])) {
                            delete obj[keys[i]];
                        }
                    } catch (e) {}
                }
            }

            try {
                var origParse = JSON.parse;
                JSON.parse = function(text, reviver) {
                    var val = origParse.call(this, text, reviver);
                    try { stripAds(val); } catch (e) {}
                    return val;
                };
            } catch (e) {}

            try {
                if (window.fetch) {
                    var origFetch = window.fetch;
                    window.fetch = function(input, init) {
                        var url = '';
                        try {
                            url = typeof input === 'string' ? input : (input && input.url) || '';
                        } catch (e) {}
                        if (url.indexOf('/youtubei/v1/player') === -1 &&
                            url.indexOf('/youtubei/v1/next') === -1) {
                            return origFetch.apply(this, arguments);
                        }
                        return origFetch.apply(this, arguments).then(function(resp) {
                            try {
                                return resp.text().then(function(text) {
                                    if (text.indexOf('adPlacements') === -1 &&
                                        text.indexOf('playerAds') === -1) {
                                        return new Response(text, {
                                            status: resp.status,
                                            statusText: resp.statusText,
                                            headers: resp.headers
                                        });
                                    }
                                    var data = origParse(text);
                                    stripAds(data);
                                    return new Response(JSON.stringify(data), {
                                        status: resp.status,
                                        statusText: resp.statusText,
                                        headers: resp.headers
                                    });
                                });
                            } catch (e) { return resp; }
                        });
                    };
                }
            } catch (e) {}

            // Fallback: skip/mute anything that still enters ad mode.
            try {
                if (window.__leanYtSkip) return;
                window.__leanYtSkip = true;
                var skipSel = '.ytp-skip-ad-button,.ytp-ad-skip-button,.ytp-skip-ad-button-modern';
                function q(s) { return document.querySelector(s); }
                function clickSkip() { var b = q(skipSel); if (b) { b.click(); } }
                function tame() {
                    var v = q('video');
                    if (!v) return;
                    if (q('.ad-showing')) {
                        if (!v.dataset.leanMuted) { v.dataset.leanMuted = '1'; }
                        v.muted = true;
                        clickSkip();
                        if (!q(skipSel) && isFinite(v.duration) && v.duration > 0 &&
                            v.duration < 180 && v.currentTime < v.duration - 0.5) {
                            try { v.currentTime = v.duration - 0.2; } catch (e) {}
                        }
                    } else if (v.dataset.leanMuted) {
                        v.muted = false;
                        delete v.dataset.leanMuted;
                    }
                }
                function start() {
                    if (!document.documentElement) {
                        requestAnimationFrame(start);
                        return;
                    }
                    setInterval(tame, 500);
                    try {
                        new MutationObserver(function() { if (q(skipSel)) { clickSkip(); } })
                            .observe(document.documentElement, { childList: true, subtree: true });
                    } catch (e) {}
                    tame();
                }
                start();
            } catch (e) {}
        })();
        """
    }

    /// Grayscale/antialiased text rendering. Off by default: removes the
    /// style node so pages fall back to the platform rasterizer.
    static func fontSmoothing(enabled: Bool) -> String {
        if !enabled {
            return """
            (function() {
                function remove() {
                    document.getElementById('lean-font-smoothing-style')?.remove();
                }
                remove();
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', remove, { once: true });
                }
            })();
            """
        }
        let css = "html body, html body * { -webkit-font-smoothing: antialiased !important; -moz-osx-font-smoothing: grayscale !important; }"
        return """
        (function() {
            function apply() {
                var style = document.getElementById('lean-font-smoothing-style');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'lean-font-smoothing-style';
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
