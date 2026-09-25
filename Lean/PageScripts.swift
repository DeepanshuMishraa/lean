import Foundation

enum PageScripts {
    static let pageReadyMessageName = "pageReady"
    static let contextMenuMessageName = "leanContextMenu"
    static let passwordFormMessageName = "leanPasswordFormSubmit"
    static let passwordFieldMessageName = "leanPasswordFieldFocus"
    static let middleClickMessageName = "leanMiddleClick"
    static let mediaStateMessageName = "leanMediaState"

    /// Reports the anchor under every right-click (empty string for
    /// non-links) so the native menu can offer "Open Link in New Tab".
    /// Always posts, so a stale URL can never linger. All frames: links
    /// often live in iframes.
    static let contextMenuLinkTracker = """
    (function() {
        try {
            document.addEventListener('contextmenu', function(e) {
                try {
                    var url = '';
                    var el = (e.target && e.target.closest) ? e.target.closest('a[href]') : null;
                    if (el) { url = el.href || ''; }
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(contextMenuMessageName)) {
                        window.webkit.messageHandlers.\(contextMenuMessageName).postMessage(url);
                    }
                } catch (err) {}
            }, true);
        } catch (e) {}
    })();
    """

    static let audioActivity = """
    (function() {
        try {
            var contexts = [];
            var wrappers = new Map();
            ['AudioContext', 'webkitAudioContext'].forEach(function(name) {
                var Original = window[name];
                if (!Original) return;
                var Wrapped = wrappers.get(Original);
                if (!Wrapped) {
                    Wrapped = new Proxy(Original, {
                        construct: function(target, args, newTarget) {
                            var context = Reflect.construct(target, args, newTarget);
                            contexts.push(new WeakRef(context));
                            return context;
                        }
                    });
                    wrappers.set(Original, Wrapped);
                }
                window[name] = Wrapped;
            });
            Object.defineProperty(window, '__leanAudioContexts', { value: contexts, configurable: true });
        } catch (error) {}
    })();
    """

    static let mediaStateTracker = """
    (function() {
        try {
            var frameId = Math.random().toString(36).substring(2);
            var timer = null;
            var lastState = null;

            function check() {
                try {
                    var mediaElements = Array.from(document.querySelectorAll('audio, video'));
                    var isPlaying = mediaElements.some(function(el) {
                        return !el.paused && !el.ended && el.readyState > 1;
                    });
                    // A running AudioContext is not sound: players (YouTube
                    // included) keep one alive long after the last audible
                    // sample, and treating it as playing stuck the tab's
                    // music icon on with nothing to hear. Only elements
                    // count here.
                    var active = isPlaying;
                    var muted = mediaElements.length > 0 && mediaElements.every(function(el) {
                        return el.muted || el.volume === 0;
                    });

                    var changed = lastState === null || lastState.isPlaying !== active || lastState.isMuted !== muted;
                    // While playing, every poll reports in (a heartbeat), not
                    // just on change: a frame that played briefly and then
                    // detached can never send its goodbye, so the native
                    // side evicts frames it stops hearing from.
                    if (changed || active) {
                        lastState = { isPlaying: active, isMuted: muted };
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(mediaStateMessageName)) {
                            window.webkit.messageHandlers.\(mediaStateMessageName).postMessage({
                                id: frameId,
                                isPlaying: active,
                                isMuted: muted
                            });
                        }
                    }
                } catch (e) {}
            }

            function scheduleCheck() {
                if (timer) clearTimeout(timer);
                timer = setTimeout(check, 100);
            }

            var events = ['play', 'playing', 'pause', 'ended', 'volumechange', 'emptied', 'ratechange', 'suspend'];
            events.forEach(function(evt) {
                window.addEventListener(evt, scheduleCheck, true);
            });

            setInterval(check, 1500);

            if (document.readyState === 'complete') {
                scheduleCheck();
            } else {
                window.addEventListener('DOMContentLoaded', scheduleCheck, true);
                window.addEventListener('load', scheduleCheck, true);
            }
        } catch (e) {}
    })();
    """

    static let passwordFieldFocus = """
    (function() {
        if (window.__leanPasswordFieldFocus) {
            if (window.__leanPasswordFieldFocusReport) window.__leanPasswordFieldFocusReport();
            return;
        }
        window.__leanPasswordFieldFocus = true;
        function isPasswordField(el) {
            return !!el && el.tagName === 'INPUT' && (el.type || '').toLowerCase() === 'password';
        }
        function looksLikeUsername(el) {
            if (!el || el.tagName !== 'INPUT') return false;
            var type = (el.type || 'text').toLowerCase();
            if (type === 'password') return false;
            if (type !== 'text' && type !== 'email' && type !== 'tel') return false;
            if (el.autocomplete === 'username' || el.autocomplete === 'email' || el.autocomplete === 'current-password') return true;
            if (type === 'email') return true;
            var hay = ((el.name || '') + ' ' + (el.id || '') + ' ' + (el.placeholder || '')).toLowerCase();
            if (hay.indexOf('user') !== -1 || hay.indexOf('email') !== -1 || hay.indexOf('login') !== -1 || hay.indexOf('account') !== -1) return true;
            // Multi-step sign-in: the username step has no password input in
            // the DOM yet, so fall back to the page itself looking like one.
            if (!document.querySelector('input[type="password"]')) {
                var pageHay = ((document.title || '') + ' ' + (location.pathname || '')).toLowerCase();
                if (pageHay.indexOf('sign') !== -1 || pageHay.indexOf('login') !== -1
                    || pageHay.indexOf('log-in') !== -1 || pageHay.indexOf('password') !== -1
                    || pageHay.indexOf('account') !== -1) return true;
            }
            return false;
        }
        function report() {
            var el = document.activeElement;
            var rect = null;
            if (isPasswordField(el) || looksLikeUsername(el)) {
                var bounds = el.getBoundingClientRect();
                if (bounds.width && bounds.height) rect = { x: bounds.left, y: bounds.top, width: bounds.width, height: bounds.height };
            }
            try {
                window.webkit.messageHandlers.\(passwordFieldMessageName).postMessage({ rect: rect });
            } catch (error) {}
        }
        var scheduled = false;
        function scheduleReport() {
            if (scheduled) return;
            scheduled = true;
            requestAnimationFrame(function() { scheduled = false; report(); });
        }
        window.__leanPasswordFieldFocusReport = report;
        document.addEventListener('focusin', report, true);
        document.addEventListener('focusout', function() { setTimeout(report, 0); }, true);
        document.addEventListener('scroll', scheduleReport, true);
        window.addEventListener('resize', scheduleReport);
        report();
    })();
    """

    static let middleClickClosePage = """
    (function() {
        document.addEventListener('auxclick', function(event) {
            if (event.button !== 1 || !event.isTrusted) return;
            var target = event.target;
            if (target && target.closest && target.closest('a[href]')) return;
            event.preventDefault();
            try { window.webkit.messageHandlers.\(middleClickMessageName).postMessage(true); } catch (error) {}
        }, true);
    })();
    """

    static let passwordFormSubmit = """
    (function() {
        document.addEventListener('submit', function(event) {
            try {
                var form = event.target;
                if (!form || !form.querySelectorAll) return;
                setTimeout(function() {
                    if (event.defaultPrevented) return;
                    var passwords = Array.from(form.querySelectorAll('input[type="password"]'));
                    var current = passwords.filter(function(field) { return field.autocomplete === 'current-password'; });
                    if (!current.length && passwords.length !== 1) return;
                    var password = current[0] || passwords[0];
                    if (!password || !password.value || password.autocomplete === 'new-password') return;
                    var username = form.querySelector('input[autocomplete="username"], input[type="email"], input[name*="user" i], input[name*="email" i], input[name*="login" i]');
                    window.webkit.messageHandlers.\(passwordFormMessageName).postMessage({
                        host: location.hostname,
                        username: username ? username.value : '',
                        password: password.value
                    });
                }, 0);
            } catch (error) {}
        }, true);
    })();
    """

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
            // Deliberately NOT !important: a page rule with any class-level
            // specificity (icon ligature fonts — Meet's Material Symbols,
            // Font Awesome — live on classes) must win over this, or icon
            // buttons render as raw text ("mic", "call_end"). Body text,
            // which only inherits its stack, still takes this rule.
            rules.append("html body, html body *:not(svg):not(svg *) { font-family: \(font.cssFamily); }")
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
            style.textContent = "\(PageScripts.jsString(css))";
        })();
        """
    }

    /// Encodes text as a JavaScript double-quoted string literal: the CSS
    /// carries family names that may hold backslashes or quotes.
    static func jsString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
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
                var seen = new WeakSet();
                var budget = 20000;
                while (stack.length && budget-- > 0) {
                    var o = stack.pop();
                    if (!o || typeof o !== 'object') continue;
                    if (seen.has(o)) continue;
                    seen.add(o);
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
                // Shared browser-side inject: only the first copy wraps,
                // so player/next responses pay one parse/strip instead of
                // nested ones.
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
                if (window.Response && Response.prototype && !window.__leanYtOrigRespJson) {
                    var origRespJson = Response.prototype.json;
                    if (origRespJson) {
                        var wrappedRespJson = function() {
                            return origRespJson.apply(this, arguments).then(function(val) {
                                try { if (window.__leanYtAdsEnabled) { stripAds(val); } } catch (e) {}
                                return val;
                            });
                        };
                        try { wrappedRespJson.__leanYtWrapped = true; } catch (e) {}
                        try { window.__leanYtOrigRespJson = origRespJson; } catch (e) {}
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
                                    var data;
                                    try {
                                        data = origParse(text);
                                        stripAds(data);
                                        return new Response(JSON.stringify(data), {
                                            status: resp.status,
                                            statusText: resp.statusText,
                                            headers: resp.headers
                                        });
                                    } catch (parseErr) {
                                        // Unparseable body: pass through untouched
                                        // rather than rejecting and failing playback.
                                        return new Response(text, {
                                            status: resp.status,
                                            statusText: resp.statusText,
                                            headers: resp.headers
                                        });
                                    }
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
                // The skip button node often exists while still disabled
                // ("Skip in 5…"). Treating mere presence as skippable stalls
                // every other skip path for the whole countdown — only honor
                // a button that is actually clickable.
                function skipButton() {
                    var btns = qAll(skipSel);
                    for (var i = 0; i < btns.length; i++) {
                        try {
                            var b = btns[i];
                            if (b && !b.disabled && b.offsetParent !== null && b.clientWidth > 0) return b;
                        } catch (e) {}
                    }
                    return null;
                }
                function clickSkip() {
                    try {
                        var btn = skipButton();
                        if (btn) { try { btn.click(); } catch (e) {} }
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
                        if (skipButton()) return;
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
                        // Track ad->content transitions: auto-resume below is
                        // only for the moments right after an ad ends. At all
                        // other times a paused video is the user's choice.
                        if (window.__leanYtWasAd && !inAd) {
                            window.__leanYtLastAdEnd = Date.now();
                            window.__leanYtUserPaused = false;
                        }
                        window.__leanYtWasAd = inAd;
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
                                        // Resume only in the seconds after an ad ends,
                                        // when the player can sit on a paused 0:00
                                        // spinner. A pause anywhere else belongs
                                        // to the user — never play over it.
                                        try {
                                            var recentAdEnd = window.__leanYtLastAdEnd &&
                                                (Date.now() - window.__leanYtLastAdEnd) < 5000;
                                            if (!window.__leanYtUserPaused && recentAdEnd &&
                                                v.paused && !v.ended && v.readyState >= 2) {
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
                            if (inAd && !skipButton()) {
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
                                                v.addEventListener('pause', function() {
                                                    try {
                                                        // Any pause outside ad mode is the
                                                        // user (or the page) — never
                                                        // auto-resume over it.
                                                        if (!q('.ad-showing')) { window.__leanYtUserPaused = true; }
                                                    } catch (e) {}
                                                });
                                                v.addEventListener('playing', function() {
                                                    try { window.__leanYtUserPaused = false; } catch (e) {}
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
                var videos = document.querySelectorAll('video');
                for (var i = 0; i < videos.length; i++) {
                    var video = videos[i];
                    if (video.dataset.leanMuted) {
                        video.muted = false;
                        delete video.dataset.leanMuted;
                    }
                    if (video.dataset.leanOrigRate !== undefined) {
                        video.playbackRate = parseFloat(video.dataset.leanOrigRate) || 1;
                        delete video.dataset.leanOrigRate;
                    }
                }
            } catch (e) {}
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
                    if (window.__leanYtOrigRespJson && window.Response) {
                        Response.prototype.json = window.__leanYtOrigRespJson;
                        window.__leanYtOrigRespJson = null;
                    }
                } catch (e) {}
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
                try { window.__leanYtWasAd = false; } catch (e) {}
                try { window.__leanYtUserPaused = false; } catch (e) {}
                try { window.__leanYtLastAdEnd = 0; } catch (e) {}
            } catch (e) {}
        })();
        """
    }
}
