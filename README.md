# Lean

Lean is a small native macOS browser built with SwiftUI, AppKit, and WebKit.

Its job is simple: open pages quickly and stay out of the way. Lean avoids permanent chrome, bundled services, and features that add more weight than value. Native macOS and WebKit behavior wins over custom machinery whenever possible.

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
- WebKit content blocking

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
