# Lean

Lean is a small native macOS browser built with SwiftUI, AppKit, and WebKit.

Its job is simple: open pages quickly and stay out of the way. Lean avoids permanent chrome, bundled services, and features that add more weight than value. Native macOS and WebKit behavior wins over custom machinery whenever possible.

Why build another browser? Every mainstream option drags in a bundled
Chromium engine with its hundred-megabyte updates and background
services, or the full weight of someone else's product scope. Lean is a
personal experiment in the opposite direction: the WebKit already on
your Mac, wrapped in just enough native UI to browse. No bundled
engine, no daemons, no accounts — a clean, minimal window onto the web.

## Known limitations

> Status: Lean is a personal experiment, not a daily driver. It is
> built to explore how quiet a browser can feel, and the gaps below
> are the price of that scope. Most of them are fixable over time;
> they are listed here so the current boundary is explicit.

Lean is a thin wrapper around `WKWebView`, so anything WebKit or the
missing browser chrome does not provide will not work. Verified by testing:

- **"Continue with Google" / third-party OAuth buttons often fail.**
  Logging into Google directly (Gmail, YouTube) works. Popup-based
  "Sign in with Google" now opens the popup as a tab and lets it close
  itself (`webViewDidClose`), so the `postMessage` handshake completes.
  Google may still refuse the flow outright for non-Safari browsers.
  Workaround: use the site's direct email/password login, or finish that
  login in Safari.
- **JavaScript dialogs, HTTP Basic auth, external links, and
  camera/microphone are handled natively.** `alert` / `confirm` /
  `prompt` show sheets, HTTP Basic shows a sign-in sheet, `mailto:` /
  `tel:` / app schemes open the target app, and camera/mic asks per
  site (remembered per origin). Client-certificate pages still fail —
  there is no certificate picker.
- **Some downloads never start.** `Content-Disposition: attachment` and
  `application/octet-stream` become downloads; other files served inline
  without them still render instead of downloading.
- **No passkeys, autofill, or Apple Pay.** Safari-only integrations
  (iCloud Passwords autofill, Touch ID passkeys, `ApplePaySession`) are
  unavailable in a third-party `WKWebView`.
- **No web push notifications or extensions.** Password-manager and
  blocker extensions cannot be installed; use copy-paste.
- **DRM video is limited.** Widevine does not exist on WebKit, and
  high-resolution Netflix/Prime/Spotify playback is Safari-only.
- **If a bank or SSO page breaks, try disabling ad blocking** in
  Settings before assuming anything else.
- **No private windows, profiles, or print support.** Web Inspector is
  available via right-click → Inspect Element.

## Install a release

1. Download the right DMG from the
   [releases page](https://github.com/DeepanshuMishraa/lean/releases):
   `Lean-<version>-arm64.dmg` for Apple Silicon,
   `Lean-<version>-x86_64.dmg` for Intel.
   (Apple menu → About This Mac shows your chip.)
2. Open the DMG, drag Lean into Applications, then eject the disk image.
3. Open Lean from Applications or Spotlight. Releases are ad-hoc signed,
   not notarized, so Gatekeeper blocks the first launch — pick one:
   - Right-click (Control-click) Lean → Open → Open in the dialog.
   - Or try opening once, then go to System Settings → Privacy &
     Security, scroll to Security, and click Open Anyway.
   - Or strip the quarantine flag in Terminal, then open normally:
     ```sh
     xattr -d com.apple.quarantine /Applications/Lean.app
     ```
     Add `sudo` in front only if permission is denied.
4. From then on Lean opens normally and updates itself in-app.

Only a paid Developer ID certificate plus notarization removes step 3.

## Principles

- Keep the interface quiet and compact
- Prefer native platform behavior
- Make every setting optional and immediate
- Add features only when they improve browsing without bloating the app

## Features

- Horizontal tabs with keyboard switching and previews
- Omnibar search, URL entry, history, and open-tab matching
- Light, dark, and system themes
- Separate Lean UI and webpage fonts
- Configurable page scrollbars and native scrolling
- Adjustable interface size (Settings → Appearance → Browser UI)
- WebKit content blocking (uBlock Origin lists + YouTube ad coverage)
- Right-click page menu (Back, Forward, Reload, View Page Source, Inspect Element)

## Run

Requires macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open Lean.xcodeproj
```

Select the `Lean` scheme and run.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘T` | New tab |
| `⌘W` | Close tab |
| `⇧⌘T` | Reopen closed tab |
| `⌃Tab` / `⌃⇧Tab` | Switch tabs |
| `⌘1`–`⌘9` | Select tab |
| `⌘L` | Focus omnibar |
| `⌘F` | Find on page |
| `⌘,` | Settings |

## Structure

```text
Lean/
├── LeanApp.swift            App entry point
├── LeanStore.swift          Tabs and persisted preferences
├── LeanTab.swift            WKWebView lifecycle and navigation
├── PageScripts.swift        Injected page styles and readiness hooks
├── LeanView.swift           Main window
├── TopBarView.swift         Tab strip and window controls
├── OmnibarView.swift        Address and search input
├── SettingsView.swift       Preferences screen
└── *Controls.swift          Focused view helpers
```

Tests live in `LeanTests/` and use Swift Testing.
