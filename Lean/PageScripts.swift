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
    /// schedule out of `youtubei/v1/player` + `/next` (+ `/browse`,
    /// `/get_watch`) responses before the player ever sees it (no ad mode,
    /// no flash, no spinner): `fetch` is wrapped for those endpoints,
    /// `Response.json` as a safety net, and `JSON.parse` for XHR-text
    /// flows. A skip/mute/speedup fallback covers anything that still slips
    /// into ad mode. Hostname-guarded; inert everywhere else. Document-start
    /// so the patches win the race with the player bootstrap.
    ///
    /// Reversible: the wrappers consult `window.__leanYtAdsEnabled` and the
    /// install is idempotent (originals saved to `__leanYtOrigParse` /
    /// `__leanYtOrigFetch`, wrapped functions marked `__leanYtWrapped`, skip
    /// interval/observer stored on `__leanYtSkipTimer` / `__leanYtSkipObserver`
    /// and guarded by `__leanYtSkip`), so re-evaluating on the live page
    /// never double-wraps. See `youtubeAdsLive(enabled:)` for live toggles.
    static func youtubeAds(enabled: Bool) -> String {
        if !enabled {
            return "void 0;"
        }
        return """
        (function() {
            try { window.__leanYtAdsEnabled = true; } catch (e) {}
            try {
                var host = location.hostname || '';
                if (!/(^|\\.)youtube\\.com$|(^|\\.)youtu\\.be$/.test(host)) return;
            } catch (e) { return; }

            function stripShallow(obj) {
                var keys = ['adPlacements', 'playerAds', 'adSlots'];
                for (var i = 0; i < keys.length; i++) {
                    try {
                        if (Object.prototype.hasOwnProperty.call(obj, keys[i])) {
                            delete obj[keys[i]];
                        }
                    } catch (e) {}
                }
            }

            function stripAds(obj) {
                if (!obj || typeof obj !== 'object') return;
                stripShallow(obj);
                // Some clients nest the schedule (contents/playabilityStatus):
                // deep-walk player-shaped responses only, with a node budget
                // and cycle guard so unrelated JSON stays cheap.
                var looksPlayer = false;
                try {
                    looksPlayer = !!(obj.playabilityStatus || obj.streamingData ||
                        (obj.responseContext && obj.contents));
                } catch (e) {}
                if (!looksPlayer) return;
                var stack = [obj];
                var seen = [];
                var budget = 20000;
                while (stack.length && budget-- > 0) {
                    var o = stack.pop();
                    if (!o || typeof o !== 'object') continue;
                    var dup = false;
                    for (var s = 0; s < seen.length; s++) {
                        if (seen[s] === o) { dup = true; break; }
                    }
                    if (dup) continue;
                    seen.push(o);
                    stripShallow(o);
                    if (o instanceof Array) {
                        for (var a = 0; a < o.length; a++) { stack.push(o[a]); }
                    } else {
                        for (var key in o) {
                            try { stack.push(o[key]); } catch (e) {}
                        }
                    }
                }
            }

            // First-load data is inline in the HTML (no request to prune),
            // so trap the globals before the player bootstrap reads them.
            // At document-start this always wins; on late injection it
            // strips whatever is already assigned. Re-defining is safe, and
            // the setter consults the flag so disable stops pruning.
            try {
                ['ytInitialPlayerResponse', 'ytInitialData'].forEach(function(name) {
                    try {
                        var current = window[name];
                        try { if (window.__leanYtAdsEnabled) { stripAds(current); } } catch (e) {}
                        Object.defineProperty(window, name, {
                            configurable: true,
                            get: function() { return current; },
                            set: function(v) {
                                try { if (window.__leanYtAdsEnabled) { stripAds(v); } } catch (e) {}
                                current = v;
                            }
                        });
                    } catch (e) {}
                });
            } catch (e) {}

            try {
                if (!window.__leanYtOrigParse) {
                    try { window.__leanYtOrigParse = JSON.parse; } catch (e) {}
                }
                var origParse = window.__leanYtOrigParse;
                // Shared with the CEF early patch (Helper) and browser-side
                // inject: only the first copy wraps, so player/next responses
                // pay one parse/strip instead of three nested ones.
                if (origParse && !JSON.parse.__leanYtWrapped && !window.__leanYtFetchPatched) {
                    var wrappedParse = function(text, reviver) {
                        var val = origParse.call(this, text, reviver);
                        try { if (window.__leanYtAdsEnabled) { stripAds(val); } } catch (e) {}
                        return val;
                    };
                    try { wrappedParse.__leanYtWrapped = true; } catch (e) {}
                    JSON.parse = wrappedParse;
                }
            } catch (e) {}

            // Safety net for fetch(...).then(r => r.json()): native JSON
            // parsing bypasses the JSON.parse wrapper above.
            try {
                if (window.Response && Response.prototype && !Response.prototype.__leanYtWrapped) {
                    var origRespJson = Response.prototype.json;
                    if (origRespJson) {
                        var wrappedRespJson = function() {
                            return origRespJson.apply(this, arguments).then(function(val) {
                                try { if (window.__leanYtAdsEnabled) { stripAds(val); } } catch (e) {}
                                return val;
                            });
                        };
                        try { wrappedRespJson.__leanYtWrapped = true; } catch (e) {}
                        Response.prototype.json = wrappedRespJson;
                    }
                }
            } catch (e) {}

            try {
                if (window.fetch && !window.__leanYtOrigFetch) {
                    try { window.__leanYtOrigFetch = window.fetch; } catch (e) {}
                }
                var origFetch = window.__leanYtOrigFetch;
                if (origFetch && window.fetch && !window.fetch.__leanYtWrapped && !window.__leanYtFetchPatched) {
                    var wrappedFetch = function(input, init) {
                        var url = '';
                        try {
                            url = typeof input === 'string' ? input : (input && input.url) || '';
                        } catch (e) {}
                        if (!window.__leanYtAdsEnabled) {
                            return origFetch.apply(this, arguments);
                        }
                        if (url.indexOf('/youtubei/v1/player') === -1 &&
                            url.indexOf('/youtubei/v1/next') === -1 &&
                            url.indexOf('/youtubei/v1/browse') === -1 &&
                            url.indexOf('/youtubei/v1/get_watch') === -1) {
                            return origFetch.apply(this, arguments);
                        }
                        return origFetch.apply(this, arguments).then(function(resp) {
                            try {
                                return resp.text().then(function(text) {
                                    try {
                                        if (!window.__leanYtAdsEnabled) {
                                            return new Response(text, {
                                                status: resp.status,
                                                statusText: resp.statusText,
                                                headers: resp.headers
                                            });
                                        }
                                    } catch (e) {}
                                    if (text.indexOf('adPlacements') === -1 &&
                                        text.indexOf('playerAds') === -1 &&
                                        text.indexOf('adSlots') === -1 &&
                                        text.indexOf('adBreakHeartbeatParams') === -1) {
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
                    try { wrappedFetch.__leanYtWrapped = true; } catch (e) {}
                    window.fetch = wrappedFetch;
                    try { window.__leanYtFetchPatched = true; } catch (e) {}
                }
            } catch (e) {}

            // Fallback: skip/mute anything that still enters ad mode.
            // Guarded by __leanYtSkip so live re-evaluation never stacks a
            // second interval/observer; tame() consults the flag.
            try {
                if (window.__leanYtSkip) return;
                window.__leanYtSkip = true;
                var skipSel = '.ytp-skip-ad-button,.ytp-ad-skip-button,.ytp-skip-ad-button-modern';
                function q(s) { try { return document.querySelector(s); } catch (e) { return null; } }
                function qAll(s) { try { return document.querySelectorAll(s); } catch (e) { return []; } }
                function clickSkip() {
                    try {
                        var btns = qAll(skipSel);
                        for (var i = 0; i < btns.length; i++) {
                            try { btns[i].click(); } catch (e) {}
                        }
                    } catch (e) {}
                    // Player API fallback: exposes skipAd() even when the
                    // button node hasn't rendered yet.
                    try {
                        var p = document.getElementById('movie_player');
                        if (p && typeof p.skipAd === 'function') { try { p.skipAd(); } catch (e) {} }
                    } catch (e) {}
                }
                function seekPastAd(v) {
                    try {
                        if (q(skipSel)) return;
                        var d = v.duration;
                        if (isFinite(d) && d > 0 && d < 180 && v.currentTime < d - 0.5) {
                            try { v.currentTime = d - 0.2; } catch (e) {}
                        } else if (!isFinite(d) || d >= 180) {
                            // DASH/long ads report Infinity or huge durations,
                            // so the finite fast-path above never fires (bar
                            // looks full while the ad keeps playing). Jump via
                            // the seekable range or a large offset instead.
                            try {
                                if (v.seekable && v.seekable.length) {
                                    var end = v.seekable.end(v.seekable.length - 1);
                                    if (isFinite(end) && end > 0 && v.currentTime < end - 0.5) {
                                        v.currentTime = end - 0.2;
                                    } else {
                                        v.currentTime = 100000;
                                    }
                                } else {
                                    v.currentTime = 100000;
                                }
                            } catch (e2) {}
                        }
                    } catch (e) {}
                }
                function tame() {
                    try {
                        if (!window.__leanYtAdsEnabled) return;
                        var inAd = !!q('.ad-showing');
                        var vids = qAll('video');
                        if (!vids || vids.length === 0) return;
                        for (var i = 0; i < vids.length; i++) {
                            (function(v) {
                                try {
                                    if (inAd) {
                                        // Only claim the mute when we actually
                                        // change it: restoring an untouched
                                        // video would steal a user's own mute.
                                        if (!v.muted && !v.dataset.leanMuted) { v.dataset.leanMuted = '1'; }
                                        v.muted = true;
                                        if (v.dataset.leanOrigRate === undefined) {
                                            try { v.dataset.leanOrigRate = String(v.playbackRate || 1); } catch (e) {}
                                        }
                                        try { v.playbackRate = 16; } catch (e) {}
                                        clickSkip();
                                        seekPastAd(v);
                                        // Keep a fast-forwarded ad moving: some
                                        // builds pause after a seek, stalling
                                        // the ad->content transition.
                                        try {
                                            if (v.paused) {
                                                var ap = v.play();
                                                if (ap && ap.catch) { ap.catch(function() {}); }
                                            }
                                        } catch (e) {}
                                    } else {
                                        if (v.dataset.leanMuted) {
                                            v.muted = false;
                                            delete v.dataset.leanMuted;
                                        }
                                        if (v.dataset.leanOrigRate !== undefined) {
                                            try { v.playbackRate = parseFloat(v.dataset.leanOrigRate) || 1; } catch (e) {
                                                try { v.playbackRate = 1; } catch (e2) {}
                                            }
                                            delete v.dataset.leanOrigRate;
                                        }
                                        // Chromium blocks unmuted autoplay
                                        // after the ad without a fresh gesture
                                        // (WebKit allows it), so resume
                                        // explicitly instead of leaving a
                                        // paused 0:00 spinner.
                                        try {
                                            if (v.paused && !v.ended && v.readyState >= 2) {
                                                var cp = v.play();
                                                if (cp && cp.catch) { cp.catch(function() {}); }
                                            }
                                        } catch (e) {}
                                    }
                                } catch (e) {}
                            })(vids[i]);
                        }
                        // During-ad player-API seek: the DOM seek above can
                        // miss DASH ads; the player seek usually doesn't.
                        try {
                            if (inAd && !q(skipSel)) {
                                var p = document.getElementById('movie_player');
                                if (p && typeof p.seekTo === 'function' && typeof p.getDuration === 'function') {
                                    var adDur = p.getDuration();
                                    if (isFinite(adDur) && adDur > 0 && adDur < 180) {
                                        try { p.seekTo(adDur, true); } catch (e) {}
                                    }
                                }
                            }
                        } catch (e) {}
                    } catch (e) {}
                }
                function start() {
                    try {
                        if (!window.__leanYtAdsEnabled) return;
                        if (!document.documentElement) {
                            requestAnimationFrame(start);
                            return;
                        }
                        try { window.__leanYtSkipTimer = setInterval(tame, 120); } catch (e) {}
                        try {
                            var obs = new MutationObserver(function() {
                                try {
                                    if (!window.__leanYtAdsEnabled) return;
                                    tame();
                                } catch (e) {}
                            });
                            obs.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] });
                            window.__leanYtSkipObserver = obs;
                        } catch (e) {}
                        try {
                            var hookVideos = function() {
                                var vs = qAll('video');
                                for (var i = 0; i < vs.length; i++) {
                                    (function(v) {
                                        try {
                                            if (!v.__leanYtHooked) {
                                                v.__leanYtHooked = true;
                                                v.addEventListener('timeupdate', function() {
                                                    try {
                                                        if (window.__leanYtAdsEnabled && q('.ad-showing')) { tame(); }
                                                    } catch (e) {}
                                                });
                                                v.addEventListener('play', function() {
                                                    try {
                                                        if (window.__leanYtAdsEnabled && q('.ad-showing')) { tame(); }
                                                    } catch (e) {}
                                                });
                                            }
                                        } catch (e) {}
                                    })(vs[i]);
                                }
                            };
                            hookVideos();
                            var bodyObs = new MutationObserver(function() { try { hookVideos(); } catch (e) {} });
                            bodyObs.observe(document.documentElement, { childList: true, subtree: true });
                            window.__leanYtVideoObserver = bodyObs;
                        } catch (e) {}
                        tame();
                    } catch (e) {}
                }
                start();
            } catch (e) {}
        })();
        """
    }

    /// Live-page companion to `youtubeAds(enabled:)`, for `evaluateJavaScript`
    /// on the current document (user scripts only affect future navigations).
    /// Enable reuses the idempotent installer; disable flips the flag,
    /// restores the saved `fetch` / `JSON.parse` originals, and clears the
    /// skip interval plus observer.
    static func youtubeAdsLive(enabled: Bool) -> String {
        if enabled {
            return youtubeAds(enabled: true)
        }
        return """
        (function() {
            try { window.__leanYtAdsEnabled = false; } catch (e) {}
            try {
                try {
                    if (window.__leanYtOrigParse) {
                        try { JSON.parse = window.__leanYtOrigParse; } catch (e) {}
                        try { window.__leanYtOrigParse = null; } catch (e) {}
                    }
                } catch (e) {}
                try {
                    if (window.__leanYtOrigFetch) {
                        try { window.fetch = window.__leanYtOrigFetch; } catch (e) {}
                        try { window.__leanYtOrigFetch = null; } catch (e) {}
                    }
                } catch (e) {}
                try { window.__leanYtFetchPatched = false; } catch (e) {}
                try {
                    if (window.__leanYtSkipTimer) {
                        try { clearInterval(window.__leanYtSkipTimer); } catch (e) {}
                        try { window.__leanYtSkipTimer = null; } catch (e) {}
                    }
                } catch (e) {}
                try {
                    if (window.__leanYtSkipObserver) {
                        try { window.__leanYtSkipObserver.disconnect(); } catch (e) {}
                        try { window.__leanYtSkipObserver = null; } catch (e) {}
                    }
                } catch (e) {}
                try {
                    if (window.__leanYtVideoObserver) {
                        try { window.__leanYtVideoObserver.disconnect(); } catch (e) {}
                        try { window.__leanYtVideoObserver = null; } catch (e) {}
                    }
                } catch (e) {}
                try { window.__leanYtSkip = false; } catch (e) {}
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
