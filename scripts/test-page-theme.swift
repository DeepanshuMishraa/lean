// Native WebKit regression harness. Run: swift scripts/test-page-theme.swift
// No browser build, packages, network requests, or page text leaves this process.
import AppKit
import WebKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let engine = try String(contentsOf: root.appendingPathComponent("Lean/Resources/page-theme.js"), encoding: .utf8)
let app = NSApplication.shared
let world = WKContentWorld.world(name: "LeanThemeTest")
let configuration = WKWebViewConfiguration()
configuration.websiteDataStore = .nonPersistent()
configuration.userContentController.addUserScript(
    WKUserScript(source: engine, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world))
/// Mirrors LeanTab: subframes announce themselves from Lean's world and the host pushes theme changes in.
final class FrameTracker: NSObject, WKScriptMessageHandler {
    var frames: [WKFrameInfo] = []
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if !message.frameInfo.isMainFrame { frames.append(message.frameInfo) }
    }
}
let tracker = FrameTracker()
configuration.userContentController.add(tracker, contentWorld: world, name: "leanThemeFrame")
let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = webView
var finished = false
var failed = false

@MainActor
func js(_ source: String) async throws -> Any? {
    try await withCheckedThrowingContinuation { continuation in
        webView.evaluateJavaScript(source, in: nil, in: world) { result in
            continuation.resume(with: result.map { Optional($0) })
        }
    }
}
func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "PageThemeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
@MainActor
func waitForScan() async throws {
    for _ in 0..<150 {
        let ready = try await js("LeanPageTheme.inspect().nodes > 0 && LeanPageTheme.inspect().pending === 0") as? Bool
        if ready == true { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    let state = try await js("JSON.stringify(LeanPageTheme.inspect())") as? String
    throw NSError(
        domain: "PageThemeTest", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Page scan did not complete within 3 seconds: \(state ?? "No diagnostics")"])
}
/// Applies a theme to the page and to every announced subframe, as the browser does.
@MainActor
func applyEverywhere(_ source: String) async throws {
    _ = try await js(source)
    for frame in tracker.frames {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript(source, in: frame, in: world) { _ in done.resume() }
        }
    }
}

@MainActor
func waitForFrame(_ expected: String) async throws {
    for _ in 0..<150 {
        let color = try await js("document.body.dataset.frameBackground") as? String
        if color == expected { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    let color = try await js("document.body.dataset.frameBackground") as? String
    let details = try await js("document.body.dataset.frameDetails") as? String
    try check(false, "Subframe background \(color ?? "nil") did not become \(expected): \(details ?? "No details")")
}
/// `#rrggbb` as the computed-style form `rgb(r, g, b)`.
func rgbString(_ hex: String) -> String {
    let n = Int(hex.dropFirst(), radix: 16) ?? 0
    return "rgb(\(n >> 16), \(n >> 8 & 255), \(n & 255))"
}

func json(_ value: [String: String]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
}

// Read the actual bundled theme definitions instead of maintaining a second palette list.
let definitions = try String(contentsOf: root.appendingPathComponent("Lean/ColorTheme.swift"), encoding: .utf8)
let pattern =
    #"ThemePalette\("(#[\da-fA-F]{6})", "(#[\da-fA-F]{6})", "(#[\da-fA-F]{6})", "(#[\da-fA-F]{6})", "(#[\da-fA-F]{6})", "(#[\da-fA-F]{6})", "(#[\da-fA-F]{6})""#
let regex = try NSRegularExpression(pattern: pattern)
let keys = ["background", "surface", "raised", "border", "text", "textMuted", "accent"]
var palettes: [[String: String]] = regex.matches(in: definitions, range: NSRange(definitions.startIndex..., in: definitions)).map { match in
    var result: [String: String] = [:]
    for (index, key) in keys.enumerated() {
        if let range = Range(match.range(at: index + 1), in: definitions) { result[key] = String(definitions[range]) }
    }
    // The opacity arguments trail the seven colours, up to the closing parenthesis.
    if let whole = Range(match.range, in: definitions) {
        let tail = definitions[whole.upperBound...].prefix { $0 != ")" }
        for name in ["borderOpacity", "mutedOpacity"] {
            if let found = tail.range(of: "\(name): ") {
                result[name] = String(tail[found.upperBound...].prefix { $0.isNumber || $0 == "." })
            }
        }
    }
    return result
}
try check(palettes.count == 18, "Expected both variants of the nine named themes")
palettes += [
    [
        "background": "#000000", "surface": "#171717", "raised": "#1f1f1f", "border": "#1f1f1f", "text": "#f0f0f0", "textMuted": "#8c8c8c",
        "accent": "#58a6ff",
    ],
    [
        "background": "#ffffff", "surface": "#ededed", "raised": "#f9f9f9", "border": "#ebebeb", "text": "#1f1f1f", "textMuted": "#858585",
        "accent": "#0969da",
    ],
]
// The browser ships opacity composited over the page and contrast floors on surface, raised and border
// (PageTheme.init). Feed the interpreter those values, not the raw palette, so the harness sees what pages do.
func channels(_ hex: String) -> [Double] {
    let n = Int(hex.dropFirst(), radix: 16) ?? 0
    return [Double(n >> 16), Double(n >> 8 & 255), Double(n & 255)]
}
func luminance(_ rgb: [Double]) -> Double {
    let v = rgb.map { c -> Double in let x = c / 255; return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    return v[0] * 0.2126 + v[1] * 0.7152 + v[2] * 0.0722
}
func contrastRatio(_ a: [Double], _ b: [Double]) -> Double {
    (max(luminance(a), luminance(b)) + 0.05) / (min(luminance(a), luminance(b)) + 0.05)
}
func hexString(_ rgb: [Double]) -> String {
    String(format: "#%02x%02x%02x", Int(rgb[0]), Int(rgb[1]), Int(rgb[2]))
}
func composite(_ hex: String, opacity: Double, over base: String) -> String {
    hexString(zip(channels(hex), channels(base)).map { ($0 * opacity + $1 * (1 - opacity)).rounded() })
}
func separated(_ hex: String, from base: String, minimum: Double) -> String {
    let color = channels(hex), ground = channels(base)
    guard contrastRatio(color, ground) < minimum else { return hex }
    let pole = contrastRatio([0, 0, 0], ground) > contrastRatio([255, 255, 255], ground) ? 0.0 : 255.0
    func mixed(_ t: Double) -> [Double] { color.map { $0 + (pole - $0) * t } }
    var low = 0.0, high = 1.0
    for _ in 0..<12 {
        let mid = (low + high) / 2
        if contrastRatio(mixed(mid), ground) >= minimum { high = mid } else { low = mid }
    }
    return hexString(mixed(high).map { pole == 0 ? $0.rounded(.down) : $0.rounded(.up) })
}
for index in 0..<palettes.count {
    guard let ground = palettes[index]["background"] else { continue }
    if let opacity = palettes[index]["borderOpacity"].flatMap(Double.init), let border = palettes[index]["border"] {
        palettes[index]["border"] = composite(border, opacity: opacity, over: ground)
    }
    if let opacity = palettes[index]["mutedOpacity"].flatMap(Double.init), let muted = palettes[index]["textMuted"] {
        palettes[index]["textMuted"] = composite(muted, opacity: opacity, over: ground)
    }
    palettes[index]["borderOpacity"] = nil
    palettes[index]["mutedOpacity"] = nil
    // Index 18 is the system dark look, whose cards and dialogs are fixed steps above black.
    for (key, floor) in [("surface", 1.15), ("raised", 1.05), ("border", 1.5)] where !(index == 18 && key != "border") {
        if let value = palettes[index][key] { palettes[index][key] = separated(value, from: ground, minimum: floor) }
    }
}
let semanticDefinitions = try String(contentsOf: root.appendingPathComponent("Lean/PageTheme.swift"), encoding: .utf8)
let casePattern = #"case \.([A-Za-z]+)(?:, \.([A-Za-z]+))?:([\s\S]*?)(?=\n        case |\n        \})"#
let cases = try NSRegularExpression(pattern: casePattern)
let semanticPattern = #"PageSemanticColors\("(#[\da-f]{6})", "(#[\da-f]{6})", "(#[\da-f]{6})", "(#[\da-f]{6})"\)"#
let semanticRegex = try NSRegularExpression(pattern: semanticPattern)
var semantics: [String: [[String: String]]] = [:]
for match in cases.matches(in: semanticDefinitions, range: NSRange(semanticDefinitions.startIndex..., in: semanticDefinitions)) {
    guard let bodyRange = Range(match.range(at: 3), in: semanticDefinitions) else { continue }
    let body = String(semanticDefinitions[bodyRange])
    let variants = semanticRegex.matches(in: body, range: NSRange(body.startIndex..., in: body)).map { colors in
        var result: [String: String] = [:]
        for (index, key) in ["danger", "success", "warning", "info"].enumerated() {
            if let range = Range(colors.range(at: index + 1), in: body) { result[key] = String(body[range]) }
        }
        return result
    }
    for group in [1, 2] {
        if let range = Range(match.range(at: group), in: semanticDefinitions) { semantics[String(semanticDefinitions[range])] = variants }
    }
}
let themeNames = ["catppuccin", "tokyoNight", "dracula", "one", "nord", "gruvbox", "rosePine", "solarized", "github", "standard"]
for i in palettes.indices {
    guard let variants = semantics[themeNames[i / 2]], let first = variants.first else {
        throw NSError(
            domain: "PageThemeTest", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing semantic colors for \(themeNames[i / 2])"])
    }
    let semantic = variants.count == 1 ? first : variants[i % 2]
    palettes[i].merge(semantic) { current, _ in current }
}

func fixture(dark: Bool, csp: Bool = false) -> String {
    let bg = dark ? "#111111" : "#ffffff"
    let fg = dark ? "#eeeeee" : "#111111"
    let surface = dark ? "#222222" : "#f0f0f0"
    return """
        <!doctype html><html><head>\(csp ? "<meta http-equiv=\"Content-Security-Policy\" content=\"style-src 'nonce-fixture'\">" : "")<style nonce="fixture">
        :root { --site-background: \(bg); --site-text: \(fg); --mixed: #123456; }
        body { background: var(--site-background); color: var(--site-text); }
        .card { background: \(surface); padding: 20px; border-radius: 12px; border: 1px solid #777; }
        .nested { background: \(dark ? "#333333" : "#e0e0e0"); padding: 10px; border-radius: 8px; }
        .muted { color: #999999; }
        .danger { background: #cc2222; color: #ffffff; }
        .danger:focus { outline: 2px solid #000; }
        .brand { background:#cc2222; color:#fff; }
        .green-link { color:#00ff00; }
        .status, .unknown-color { color:#ff3333; }
        .clear { background: transparent; }
        .badge::before { content: 'Badge'; color: \(fg); background: \(surface); padding: 4px; }
        pre .syntax { color: #ff3333; }
        .card:hover { background: #444; }
        .glass { background: rgba(30,30,30,.5); padding:12px; border-radius:8px; }
        .modern { background: oklch(90% 0 0); padding:12px; border-radius:8px; }
        .uncertain { background:#888; width:100px; height:40px; }
        .pinned { position:fixed; top:0; left:0; width:200px; height:40px; background:\(bg); }
        .warn-card { border-color:#661111; }
        .scrim { position:fixed; top:0; right:0; width:120px; height:60px; background:rgba(0,0,0,.65); }
        .dlg-part { background:\(bg); padding:4px; border-radius:4px; }
        .dlg-body { background:\(surface); padding:4px; }
        .fade { height:40px; background-image:linear-gradient(rgba(0,0,0,0), rgb(0,0,0)); }
        </style></head><body style="background-color:\(bg) !important; color:\(fg) !important;"><h1>Heading</h1><div class="card" style="background-color:\(surface) !important; border-color:#777 !important;">Card <span class="muted">Muted</span>
        <div class="nested">Nested card</div></div><button class="danger">Delete</button>
        <button class="brand">Subscribe</button><a class="green-link" href="#">Link</a>
        <span class="status" role="status">Error</span><span class="unknown-color">Colored content</span>
        <h3 class="video-heading"><a href="#video"><span>Video title</span></a></h3>
        <div class="clear">Transparent</div><div class="badge">Badge</div><pre><span class="syntax">Syntax</span></pre>
        <img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7" width="40" height="40">
        <svg width="100" height="100"><rect width="100" height="100" fill="#ff0000"/></svg>
        <svg id="icon" width="16" height="16"><path d="M0 0h16v16H0z" fill="#000000"/></svg>
        <svg id="logo" aria-label="Company logo" width="16" height="16"><path d="M0 0h16v16H0z" fill="#000000"/></svg>
        <svg id="two-color" width="16" height="16"><rect width="16" height="16" fill="#fff"/><circle cx="8" cy="8" r="4" fill="#000"/></svg>
        <svg id="inherited-art" width="80" height="80"><path d="M0 0h80v80H0z" fill="currentColor"/></svg>
        <div class="glass">Translucent</div><div class="modern">Modern CSS</div><div class="uncertain">Uncertain</div>
        <div class="pinned">Header</div>
        <div class="warn-card card">Warning card</div><div class="fade"></div><div class="scrim"><div role="dialog" class="dlg"><div class="dlg-part">Dialog panel</div><div class="dlg-body">Dialog body</div></div></div>
        <div id="host"></div><div id="late-host"></div><div class="dynamic">Dynamic</div>
        <script>document.querySelector('#host').attachShadow({mode:'open'}).innerHTML = '<style nonce="fixture">.panel{background:\(surface);padding:12px;border-radius:8px;color:\(fg)}</style><div class="panel">Shadow content</div>';</script>
        </body></html>
        """
}

let liveContrastAudit = """
    (() => {
        const parse = value => {const m=/^rgba?\\(([^)]+)\\)$/.exec(value);if(!m)return null;const c=m[1].split(',').map(Number);return c.slice(0,3).concat(c.length>3?c[3]:1);};
        const blend = (a,b) => a.slice(0,3).map((v,i)=>v*a[3]+b[i]*(1-a[3])).concat(1);
        const lum = c => {const v=c.slice(0,3).map(x=>{x/=255;return x<=.04045?x/12.92:((x+.055)/1.055)**2.4});return v[0]*.2126+v[1]*.7152+v[2]*.0722;};
        let checked=0, skipped=0;const failures=[];
        for(const el of document.querySelectorAll('[data-lean-theme-color]')) {
            if(![...el.childNodes].some(n=>n.nodeType===Node.TEXT_NODE&&n.textContent.trim()))continue;
            const r=el.getBoundingClientRect(),style=getComputedStyle(el);
            if(!r.width||!r.height||r.bottom<0||r.top>innerHeight||style.visibility!=='visible')continue;
            const stack=[];let unsafe=false;
            for(let node=el;node;node=node.parentElement) {const s=getComputedStyle(node);if(s.backgroundImage!=='none'||Number(s.opacity)<1)unsafe=true;stack.push(parse(s.backgroundColor));}
            const fg=parse(style.color);if(unsafe||!fg||stack.some(c=>!c)){skipped++;continue;}
            let bg=[255,255,255,1];for(const c of stack.reverse())bg=blend(c,bg);
            const a=lum(blend(fg,bg)),b=lum(bg),ratio=(Math.max(a,b)+.05)/(Math.min(a,b)+.05);
            const large=parseFloat(style.fontSize)>=24||(parseFloat(style.fontSize)>=18.66&&Number(style.fontWeight)>=700);
            checked++;if(ratio<(large?3:4.5)-.01)failures.push({tag:el.tagName,foreground:style.color,background:bg.slice(0,3),ratio});
        }
        globalThis.__leanAuditViolations=failures.length;
        globalThis.__leanAuditChecked=checked;
        globalThis.__leanAuditSkipped=skipped;
        return JSON.stringify({checked,skipped,failures:failures.slice(0,8),graph:LeanPageTheme.inspect()});
    })()
    """

@MainActor
func saveSnapshot(_ url: URL) async throws {
    let image: NSImage = try await withCheckedThrowingContinuation { continuation in
        webView.takeSnapshot(with: nil) { image, error in
            if let image { continuation.resume(returning: image) }
            else { continuation.resume(throwing: error ?? NSError(domain: "PageThemeTest", code: 6, userInfo: [NSLocalizedDescriptionKey: "WebKit snapshot returned no image"])) }
        }
    }
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PageThemeTest", code: 7, userInfo: [NSLocalizedDescriptionKey: "Could not encode WebKit snapshot as PNG"])
    }
    try png.write(to: url, options: .atomic)
}

@MainActor
func performanceProbe() async throws {
    let rows = (0..<1000).map { "<article class='card'><h3><a href='#row'><span>Row \($0)</span></a></h3><p>Body text</p></article>" }.joined()
    webView.loadHTMLString("<html><head><style>body{background:#fff;color:#111}.card{background:#eee;padding:8px;border-radius:4px}</style></head><body>\(rows)</body></html>", baseURL: URL(string: "https://theme.test"))
    let loadDeadline = Date(timeIntervalSinceNow: 10)
    while webView.isLoading && Date() < loadDeadline { try await Task.sleep(for: .milliseconds(20)) }
    try check(!webView.isLoading, "Performance fixture did not load within 10 seconds")
    _ = try await js("""
    (() => {
        const d = Object.getOwnPropertyDescriptor(StyleSheet.prototype, 'disabled');
        if (!d?.set) throw new Error('Cannot instrument StyleSheet.disabled');
        globalThis.__themeSheetPauses = 0;
        Object.defineProperty(StyleSheet.prototype, 'disabled', {...d, set(value) {
            if (value) globalThis.__themeSheetPauses++;
            d.set.call(this, value);
        }});
    })();
    """)
    _ = try await js("LeanPageTheme.apply(\(try json(palettes[0])))")
    try await waitForScan()
    _ = try await js("globalThis.__themeSheetPauses = 0; void 0;")
    let start = Date()
    for i in 0..<30 {
        _ = try await js("""
        (() => {
            const target = document.querySelector('h3 span');
            target.dispatchEvent(new Event('pointerover', {bubbles:true}));
            document.body.dataset.animationTick = '\(i)';
            target.setAttribute('aria-label', 'Row \(i)');
        })();
        """)
        try await Task.sleep(for: .milliseconds(30))
    }
    // The hover debounce is 150 ms; let it fire before reading the counter.
    try await Task.sleep(for: .milliseconds(300))
    try await waitForScan()
    let pauses = try await js("globalThis.__themeSheetPauses") as? Int
    print("Interaction probe: \(Int(Date().timeIntervalSince(start) * 1000)) ms, \(pauses ?? -1) whole-sheet pauses")
    try check(pauses == 0, "Ordinary hover/irrelevant DOM updates suspend every theme sheet and force page-wide restyling")
}

Task { @MainActor in
    defer { finished = true }
    do {
        if CommandLine.arguments.contains("--perf") {
            try await performanceProbe()
            return
        }
        if CommandLine.arguments.contains("--live") {
            let artifacts = root.appendingPathComponent(".pi/artifacts/page-theme-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
            for (site, address) in [("github", "https://github.com/torvalds/linux"), ("youtube", "https://www.youtube.com/")] {
                guard let url = URL(string: address) else { throw NSError(domain: "PageThemeTest", code: 5) }
                webView.load(URLRequest(url: url))
                let loadDeadline = Date(timeIntervalSinceNow: 35)
                while webView.isLoading && Date() < loadDeadline { try await Task.sleep(for: .milliseconds(100)) }
                let loadState = try await js("JSON.stringify({url:location.href,state:document.readyState,body:document.body?.childElementCount||0})") as? String
                try check(!webView.isLoading, "\(site) navigation did not finish within 35 seconds: \(loadState ?? "No state")")
                try await Task.sleep(for: .seconds(2))
                try await saveSnapshot(artifacts.appendingPathComponent("\(site)-original.png"))
                for index in [0, 1] {
                    _ = try await js("LeanPageTheme.apply(\(try json(palettes[index])))")
                    try await waitForScan()
                    try await Task.sleep(for: .milliseconds(300))
                    let bg = try await js("getComputedStyle(document.body).backgroundColor") as? String
                    try check(bg == (rgbString(palettes[index]["background"] ?? "")), "\(site) canvas mismatch: \(bg ?? "nil")")
                    let report = try await js(liveContrastAudit) as? String
                    print("\(site) \(index == 0 ? "dark" : "light"): \(report ?? "No audit result")")
                    let violations = try await js("globalThis.__leanAuditViolations") as? Int
                    let audited = try await js("globalThis.__leanAuditChecked") as? Int
                    let passed = try await js("globalThis.__leanAuditSkipped") as? Int
                    try check((audited ?? 0) >= 20 && (audited ?? 0) >= (passed ?? 0) / 4, "\(site) audit sampled too little text (\(audited ?? 0) checked, \(passed ?? 0) skipped)")
                    try check(violations == 0, "\(site) has computed text-contrast failures")
                    try await saveSnapshot(artifacts.appendingPathComponent("\(site)-\(index == 0 ? "dark" : "light").png"))
                }
                _ = try await js("LeanPageTheme.apply(null)")
            }
            print("Live audit evidence: \(artifacts.path)")
            return
        }
        for (dark, csp) in [(false, false), (true, false), (true, true)] {
            tracker.frames.removeAll()
            webView.loadHTMLString(fixture(dark: dark, csp: csp), baseURL: URL(string: "https://theme.test"))
            let deadline = Date(timeIntervalSinceNow: 10)
            while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            try check(!webView.isLoading, "Local fixture did not load within 10 seconds")
            for (index, palette) in palettes.enumerated() {
                _ = try await js("LeanPageTheme.apply(\(try json(palette)))")
                try await waitForScan()
                let assertions = """
                    (() => {
                        const p = \(try json(palette));
                        const rgb = hex => {const n=parseInt(hex.slice(1),16);return `rgb(${n>>16}, ${n>>8&255}, ${n&255})`;};
                        const style = (s, pseudo) => getComputedStyle(document.querySelector(s), pseudo);
                        const failures = [];
                        const equal = (a,b,name) => {if(a!==b) failures.push(`${name}: ${a} != ${b}`);};
                        equal(style('body').backgroundColor,rgb(p.background),'canvas');
                        equal(style('.video-heading a span').color,style('.video-heading').color,'heading link must use primary text, not accent');
                        equal(style('.card').backgroundColor,rgb(p.surface),'surface');
                        equal(style('.nested').backgroundColor,rgb(p.raised),'nested surface');
                        equal(style('.card').borderTopColor,rgb(p.border),'border');
                        equal(style('.dlg-part').backgroundColor,rgb(p.raised),'a dialog panel that matches the page is raised, not a card');
                        equal(style('.dlg-body').backgroundColor,rgb(p.raised),'a borderless dialog body belongs to the dialog sheet');
                        equal(style('.pinned').backgroundColor,rgb(p.background),'pinned header must match the page background');
                        equal(style('.warn-card').borderTopColor,rgb(p.border),'tinted card border must match other cards');
                        if (!style('.fade').backgroundImage.includes(rgb(p.background).slice(4, -1))) failures.push('fade gradient kept the site colors: ' + style('.fade').backgroundImage);
                        equal(style('.modern').backgroundColor,rgb(p.surface),'OKLCH surface');
                        equal(style('.uncertain').backgroundColor,'rgb(136, 136, 136)','low confidence surface');
                        equal(style('.glass').backgroundColor,rgb(p.surface).replace('rgb(', 'rgba(').replace(')', ', 0.5)'),'surface alpha');
                        equal(style('.clear').backgroundColor,'rgba(0, 0, 0, 0)','transparency');
                        equal(style('img').filter,'none','image');
                        equal(style('svg rect').fill,'rgb(255, 0, 0)','illustration');
                        equal(style('#logo path').fill,'rgb(0, 0, 0)','labelled logo');
                        equal(style('#two-color rect').fill,'rgb(255, 255, 255)','two-color icon background');
                        equal(style('#two-color circle').fill,'rgb(0, 0, 0)','two-color icon foreground');
                        equal(style('#inherited-art path').fill,'\(dark ? "rgb(238, 238, 238)" : "rgb(17, 17, 17)")','inherited artwork');
                        equal(style('.syntax').color,'rgb(255, 51, 51)','syntax highlighting');
                        equal(style('.danger').backgroundColor,rgb(p.danger),'danger background');
                        equal(style('.brand').backgroundColor,rgb(p.accent),'red brand action is not danger');
                        if (!document.querySelector('.green-link').getAttribute('data-lean-theme-color')?.startsWith('accent-')) failures.push('link was mistaken for success');
                        if (!document.querySelector('.status').getAttribute('data-lean-theme-color')?.startsWith('danger-')) failures.push('status lost danger intent');
                        if (!document.querySelector('.unknown-color').getAttribute('data-lean-theme-color')?.startsWith('preserve-')) failures.push('unknown color intent was invented');
                        if (style('#icon path').fill === 'rgb(0, 0, 0)' && p.background !== '#ffffff') failures.push('monochrome icon left black');
                        const shadow = document.querySelector('#host').shadowRoot;
                        equal(getComputedStyle(shadow.querySelector('.panel')).backgroundColor,rgb(p.surface),'shadow surface');
                        equal(style('.badge','::before').backgroundColor,rgb(p.surface),'pseudo surface');
                        const lum = c => {const v=c.match(/[\\d.]+/g).slice(0,3).map(Number).map(x=>{x/=255;return x<=.04045?x/12.92:((x+.055)/1.055)**2.4});return v[0]*.2126+v[1]*.7152+v[2]*.0722;};
                        const ratio = (a,b) => (Math.max(lum(a),lum(b))+.05)/(Math.min(lum(a),lum(b))+.05);
                        for(const [s,bg] of [['.muted',style('.card').backgroundColor],['.danger',style('.danger').backgroundColor]]) {
                            if(ratio(style(s).color,bg)<4.5) failures.push(`${s} contrast < 4.5`);
                        }
                        if (ratio(style('.danger').borderTopColor, style('.danger').backgroundColor) < 3) failures.push('control border contrast < 3');
                        return failures.join('\\n');
                    })()
                    """
                let failures = try await js(assertions) as? String
                try check(failures == "", "Palette \(index), source \(dark ? "dark" : "light"):\n\(failures ?? "No result")")
            }
            // CSS variables are inferred from usage, not overwritten just because of their name.
            let variables =
                try await js("getComputedStyle(document.documentElement).getPropertyValue('--site-background').trim()") as? String
            try check(
                variables == "rgb(255, 255, 255)" || variables == "rgba(255, 255, 255, 1)",
                "Semantic CSS variable was not remapped: \(variables ?? "nil")")
            let graphSize = try await js("LeanPageTheme.inspect().nodes") as? Int
            _ = try await js("LeanPageTheme.apply(\(try json(palettes[0])))")
            let switchedGraphSize = try await js("LeanPageTheme.inspect().nodes") as? Int
            try check(graphSize == switchedGraphSize, "Theme switch discarded the page graph")
            _ = try await js("LeanPageTheme.apply({background: '#000000'})")
            let preserved = try await js("getComputedStyle(document.body).backgroundColor") as? String
            try check(preserved == rgbString(palettes[0]["background"] ?? ""), "Invalid palette must leave the valid theme intact")
            _ = try await js("LeanPageTheme.apply(\(try json(palettes[19])))")
            // SPA mutations and a late open shadow root are handled without page-world hooks.
            _ = try await webView.evaluateJavaScript(
                """
                document.querySelector('.dynamic').innerHTML='<div class="card">New card</div>';
                document.querySelector('#late-host').attachShadow({mode:'open'}).innerHTML='<style nonce="fixture">.late{background:#eee;padding:10px;border-radius:8px}</style><div class="late">Late shadow</div>';
                """)
            try await Task.sleep(for: .milliseconds(3200))
            try await waitForScan()
            let expected = "rgb(237, 237, 237)"
            let dynamic = try await js("getComputedStyle(document.querySelector('.dynamic .card')).backgroundColor") as? String
            try check(dynamic == expected, "SPA card did not receive the surface token")
            let shadow =
                try await js("getComputedStyle(document.querySelector('#late-host').shadowRoot.querySelector('.late')).backgroundColor")
                as? String
            try check(shadow == expected, "Late shadow root did not receive surface token: \(shadow ?? "nil")")
            // Silent CSSOM edits must be observed without monkey-patching the page's JS realm.
            // Seed a themed neutral background first, so the edit below can only pass if the engine notices it.
            _ = try await webView.evaluateJavaScript(
                "document.styleSheets[0].insertRule('.dynamic { background-color: #eeeeee; padding: 8px; border-radius: 6px; }', document.styleSheets[0].cssRules.length); void 0;"
            )
            try await Task.sleep(for: .milliseconds(3200))
            try await waitForScan()
            let seeded = try await js("document.querySelector('.dynamic').hasAttribute('data-lean-theme-background-color')") as? Bool
            try check(seeded == true, "Seed rule must be themed before the CSSOM edit")
            _ = try await webView.evaluateJavaScript(
                "document.styleSheets[0].insertRule('.dynamic { background-color: #ff00ff !important; }', document.styleSheets[0].cssRules.length); void 0;"
            )
            try await Task.sleep(for: .milliseconds(3200))
            try await waitForScan()
            let cssom = try await js("getComputedStyle(document.querySelector('.dynamic')).backgroundColor") as? String
            try check(cssom == "rgb(255, 0, 255)", "CSSOM change must replace stale neutral-surface inference")
            let stale = try await js("document.querySelector('.dynamic').hasAttribute('data-lean-theme-background-color')") as? Bool
            try check(stale == false, "Engine kept its neutral-surface override after the CSSOM edit")
            // An author can update an important inline declaration while we are active.
            _ = try await webView.evaluateJavaScript(
                "document.querySelector('.card').style.setProperty('border-top-color', '#666666', 'important');")
            try await Task.sleep(for: .milliseconds(60))
            try await waitForScan()
            let frameHTML =
                "<html><head><style nonce='fixture'>body{background:#fff;color:#111}</style></head><body>Sandboxed frame<script>setInterval(()=>parent.postMessage({type:'fixture-colors',background:getComputedStyle(document.body).backgroundColor,annotated:document.body.getAttribute('data-lean-theme-background-color'),sheets:document.adoptedStyleSheets.length,styles:document.querySelectorAll('[data-lean-theme-sheet]').length},'*'),50)</script></body></html>"
            _ = try await webView.evaluateJavaScript(
                """
                window.__themeLeaks = [];
                window.addEventListener('message', event => {
                    if (String(event.data?.type || '').startsWith('lean-page-theme')) window.__themeLeaks.push(event.data.type);
                });
                window.addEventListener('message', event => {
                    if (event.data?.type === 'fixture-colors' && document.body.dataset.frameBackground !== event.data.background)
                        document.body.dataset.frameBackground = event.data.background;
                    if (event.data?.type === 'fixture-colors') {
                        const details = JSON.stringify(event.data);
                        if (document.body.dataset.frameDetails !== details) document.body.dataset.frameDetails = details;
                    }
                });
                const child = document.createElement('iframe'); child.id = 'fixture-frame';
                child.sandbox = 'allow-scripts'; child.srcdoc = \(try json(["html": frameHTML])).html;
                document.body.appendChild(child); void 0;
                """)
            for _ in 0..<100 where tracker.frames.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
            try check(!tracker.frames.isEmpty, "Subframe never announced itself to the host")
            try await waitForFrame("rgb(255, 255, 255)")
            let isolated =
                try await js(
                    "(()=>{try {document.querySelector('#fixture-frame').contentWindow.document;return false;}catch{return true;}})()")
                as? Bool
            try check(isolated == true, "Fixture must exercise the cross-origin DOM boundary")
            try await applyEverywhere("LeanPageTheme.apply(\(try json(palettes[0])))")
            try await waitForFrame(rgbString(palettes[0]["background"] ?? ""))
            try await applyEverywhere("LeanPageTheme.apply(null)")
            try await waitForFrame("rgb(255, 255, 255)")
            let leaks = try await webView.evaluateJavaScript("window.__themeLeaks.length") as? Int
            try check(leaks == 0, "Page scripts observed \(leaks ?? -1) theme messages; theme state must not be page-visible")
            let restored =
                try await js(
                    "document.querySelectorAll('[data-lean-theme-background-color],[data-lean-theme-color],[data-lean-theme-sheet]').length"
                ) as? Int
            try check(restored == 0, "Toggle off left theme annotations or sheets")
            let restoredShadow =
                try await js(
                    "document.querySelector('#host').shadowRoot.querySelectorAll('[data-lean-theme-background-color],[data-lean-theme-color],[data-lean-theme-sheet]').length"
                ) as? Int
            try check(restoredShadow == 0, "Toggle off left shadow-root overrides")
            let sourceVariable =
                try await js("getComputedStyle(document.documentElement).getPropertyValue('--site-background').trim()") as? String
            try check(sourceVariable == (dark ? "#111111" : "#ffffff"), "Toggle off did not restore the site's CSS variables")
            let authoredBorder = try await js("getComputedStyle(document.querySelector('.card')).borderTopColor") as? String
            try check(authoredBorder == "rgb(102, 102, 102)", "Toggle off overwrote a newer site-authored important value")
            let bg = try await js("getComputedStyle(document.body).backgroundColor") as? String
            try check(bg == (dark ? "rgb(17, 17, 17)" : "rgb(255, 255, 255)"), "Toggle off did not restore original background")
            _ = try await js("LeanPageTheme.apply(\(try json(palettes[0])))")
            try await waitForScan()
        }
        // Large pages build a skeleton graph, classify visible content first, and promote nodes on scroll.
        let rows = (0..<1000).map { "<article class='card'><h2>Row \($0)</h2><p>Body text</p></article>" }.joined()
        webView.loadHTMLString(
            "<html><head><style>body{background:#fff;color:#111}.card{background:#eee;padding:8px;border-radius:4px}</style></head><body>\(rows)</body></html>",
            baseURL: URL(string: "https://theme.test"))
        let loadDeadline = Date(timeIntervalSinceNow: 10)
        while webView.isLoading && Date() < loadDeadline { try await Task.sleep(for: .milliseconds(20)) }
        try check(!webView.isLoading, "Large fixture did not load")
        let scanStart = Date()
        _ = try await js("LeanPageTheme.apply(\(try json(palettes[0])))")
        try await waitForScan()
        let nodes = try await js("LeanPageTheme.inspect().nodes") as? Int
        try check((nodes ?? 0) >= 3002, "Large fixture did not build its role graph")
        let initialScanMS = Int(Date().timeIntervalSince(scanStart) * 1000)
        _ = try await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight); void 0;")
        try await Task.sleep(for: .milliseconds(100))
        try await waitForScan()
        let lastSurface = try await js("getComputedStyle(document.querySelector('article:last-child')).backgroundColor") as? String
        try check(lastSurface == rgbString(palettes[0]["surface"] ?? ""), "Scrolling did not promote the offscreen card into the theme graph")
        // A change made while the card is offscreen must not leave the old theme in place when it scrolls back.
        _ = try await webView.evaluateJavaScript("window.scrollTo(0, 0); void 0;")
        try await Task.sleep(for: .milliseconds(300))
        try await waitForScan()
        _ = try await webView.evaluateJavaScript("document.querySelector('article:last-child').style.background = '#ff00ff'; void 0;")
        try await Task.sleep(for: .milliseconds(300))
        try await waitForScan()
        _ = try await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight); void 0;")
        try await Task.sleep(for: .milliseconds(300))
        try await waitForScan()
        let recolored = try await js("getComputedStyle(document.querySelector('article:last-child')).backgroundColor") as? String
        try check(recolored == "rgb(255, 0, 255)", "Offscreen change kept its stale theme: \(recolored ?? "nil")")
        print("Large fixture: \(nodes ?? 0) graph nodes, \(initialScanMS) ms visible-first scan; deferred scrolling passed")
        print(
            "Passed: 20 variants × light/dark/CSP pages; contrast, hierarchy, confidence, CSSOM/variables/OKLCH, inline-important restoration, alpha, SVG/media, pseudo-elements, shadow DOM, SPA mutations, isolated-frame switches, disable/re-enable"
        )
    } catch {
        failed = true
        fputs("\(error.localizedDescription)\n", stderr)
    }
}
// An explicit deadline makes this usable in unattended checks.
let deadline = Date(timeIntervalSinceNow: CommandLine.arguments.contains("--live") ? 150 : 90)
while !finished && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
if !finished { fputs("WebKit harness timed out\n", stderr) }
exit(failed || !finished ? 1 : 0)
