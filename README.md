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

> Status: Lean is usable every day now — default-browser support, full
> browser-data import (bookmarks, history, passwords), Keychain-backed
> passwords, passkeys, and extension support have all landed. What remains
> is mostly WebKit hard boundaries and small rough edges.

What's left, verified by testing:

- **Extensions mostly work, some might not.** Install from the Chrome
  Web Store or unpacked, with permission grants. Extension toolbar
  popups and tab/window APIs are not wired up, so anything depending
  on those stays inert.
- **DRM: FairPlay plays, Widevine doesn't.** FairPlay-protected video
  works out of the box through WebKit. Widevine/PlayReady need a CDM
  that only ships with Chromium, so Widevine-only players
  (Netflix/Prime/Spotify web) stay dark — no app code can fix that
  inside `WKWebView`.
- **Passkeys need Apple's browser entitlement to reach the sheet.** The
  Mac's passkey sheet (Touch ID, iCloud Keychain, QR code, security keys)
  is gated by the `com.apple.developer.web-browser.public-key-credential`
  entitlement, which Apple grants to browsers on request. Current ad-hoc
  releases don't carry it, so explicit passkey requests are attempted but
  fall back to the site's password when macOS refuses; passkeys suggested
  under the name field (conditional mediation) don't yet either way.
  `ApplePaySession` is Safari-only, so Apple Pay stays out — no app code
  can fix that inside `WKWebView`.
- **iCloud Passwords works through Apple's Chrome extension**, paired to
  its helper with Apple's code (one tap in Settings → Extensions),
  rather than through Safari's built-in autofill, which Apple keeps
  behind an entitlement no other browser gets. Lean's own Keychain
  password fill (page menu, Touch ID) works fine alongside it.
- **No web push notifications.**
- **Client-certificate pages fail.** There is no certificate picker.
- **No private windows or profiles.**
- **If a bank or SSO page breaks, try disabling ad blocking** in
  Settings before assuming anything else.

Anything else you hit is likely a bug, not a boundary — file it with
the version number (Settings → General) and steps to reproduce.

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

- Set Lean as the default browser (Settings → General); links from
  other apps open in the current or a new tab
- Import from Chrome, Arc, Dia, Helium, or Safari: bookmarks, history,
  saved passwords, and extensions (decrypted locally from the browser,
  never uploaded; Arc tabs come from its sidebar store, each extension
  gets its own permission review before it runs)
- Keychain-backed passwords with Touch ID fill and save prompts
- Extension support on macOS 15.4+: Chrome Web Store and unpacked
  installs, permission grants, content scripts
- Horizontal tabs with keyboard switching and previews
- Omnibar search, URL entry, history, and open-tab matching
- Light, dark, and system themes
- Separate Lean UI and webpage fonts
- Configurable page scrollbars and native scrolling
- Adjustable interface size (Settings → Appearance → Browser UI)
- WebKit content blocking (uBlock Origin lists + YouTube ad coverage)
- Right-click page menu (Open Link in New Tab, Print, View Page Source, Inspect Element)
- Native `alert` / `confirm` / `prompt`, HTTP Basic sign-in, external
  (`mailto:`, `tel:`, app schemes) links, and per-site camera/mic prompts
- Printing via `⌘P` with the system print panel

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
| `⌘P` | Print page |
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
