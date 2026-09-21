# CEF opt-in engine (macOS)

Default stays WebKit. CEF is opt-in via Settings → Browsing → Rendering Engine,
applies to newly opened tabs only. Shell chrome (top bar, omnibar, sidebar,
settings) is identical for both engines.

Current state: selection + per-tab plumbing + `CEFIntegration.isAvailable()`
probe exist. The CEF framework is NOT bundled yet, so CEF tabs render an
in-content notice and WebKit keeps working.

## What CEF fixes vs what it does not

Fixes: Google OAuth UA blocks, client-cert picker (via callback + custom UI),
full download control, web push, profiles/private windows, print, release DevTools.
Partial: passkeys/WebAuthn yes, built-in password autofill no (custom UI needed),
Widevine only with a `proprietary_codecs=true ffmpeg_branding=Chrome` build.
Does NOT fix: Chrome extensions (CEF exposes only a subset, no Web Store),
Apple Pay / iCloud Passwords (Safari entitlements only).

## Bring-up checklist

1. Download the matching CEF binary distribution (same Chromium branch for
   arm64 + x86_64) from https://cef-builds.spotifycdn.com/index.html
2. Add `Chromium Embedded Framework.framework` to `Lean/Frameworks/` (git-ignored,
   fetched at build time via `scripts/fetch-cef.sh` — to be added).
3. Add helper targets in `project.yml`: `Lean Helper (GPU)`, `Lean Helper
   (Renderer)`, `Lean Helper (Plugin)` with matching bundle IDs
   (`com.dipxsy.lean.helper.*`), `LSUIElement=true`, hardened runtime, and the
   Chromium `Info.plist` keys (`CFBundleURLTypes` excluded).
4. Add an ObjC++ bridge (`Lean/CEFBridge.mm` + `Lean/CEFEngineView.swift`):
   `CefInitialize` on a dedicated thread, `CefBrowserHost::CreateBrowser`
   hosted in a `CefBrowserView` → `NSView`, callbacks for title/URL/loading,
   dialogs, downloads, permissions mapped onto the existing `LeanTab` policy
   points (`ExternalLinkPolicy`, `DownloadPolicy`, `MediaPermissionStore`).
5. In `LeanView`, swap the `CEFUnavailableView` branch for `CEFEngineView`
   when `CEFIntegration.isAvailable()` is true. Keep the notice as fallback.
6. Wire `ContentBlocker` rules to `CefRequestHandler` (WebKit content blockers
   do not apply to CEF) and map find/zoom/snapshot onto CEF equivalents.
7. Sign all helpers + framework with the same Team ID; keep Sparkle updates
   working (helpers live inside `Contents/Frameworks/`).

## Layout constraint (mandated by Chromium)

```
Lean.app/Contents/Frameworks/Chromium Embedded Framework.framework
Lean.app/Contents/Frameworks/Lean Helper (GPU).app
Lean.app/Contents/Frameworks/Lean Helper (Renderer).app
...
```

`CEFIntegration.frameworkURL(bundle:)` probes exactly this layout.
