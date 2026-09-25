# Changelog

All notable changes to Lean are documented here. Lean is currently in
**alpha**: expect rough edges (see `README.md` Known limitations) and
update often — releases arrive through the built-in updater.

## [Unreleased]

### Added

- iCloud Passwords installs in one tap from Settings → Extensions (same
  review as any extension) instead of hunting the Chrome Web Store —
  Apple doesn't let anyone bundle it, so every browser fetches it there

### Fixed

- Failed navigations show a proper error page instead of a blank tab:
  server not found, connection refused (with a dev-server hint on
  localhost), offline, timeouts, and private-connection errors each get
  an explanation with Reload and Back — appearing immediately, not on
  the next tab switch

- Downloads stuck at 100% now finish: when the bytes are fully accounted
  and on disk but WebKit never delivers its finish callback, the download
  finalizes from its own accounting instead of spinning forever
- Typing a loopback server address (`localhost:3000`, `127.0.0.1:8000`)
  shows a single "Open local server" row — no history, no search row — so
  Enter always opens the server, even with a past search for it. Bare
  `localhost` still lists everything but navigates first
- Custom page fonts no longer break icon fonts: the family override yields
  to page-specified families, so Meet's buttons render as icons instead of
  raw text ("mic", "call_end")
- Camera/microphone answers are mirrored to UserDefaults as well as the
  database, so a grant survives even when the database is unavailable

### Added

- The top tab strip can take its colour from the page: Settings → Tabs →
  Colour the tab bar from the page, off by default. Tints the strip with
  what the page itself declares with `theme-color` — no sampling, no
  guessing — staying inside the browser theme so the row stays legible,
  and follows the active tab. The sidebar layout is unaffected (ported
  from [Search #168](https://github.com/driceroland/Search/pull/168))
- Peek at a link with a shift-click: Settings → General, off by default.  The link opens in a panel over the page, which stays where it was
  underneath. Escape, ⌘W or a click beside it puts it away; keeping it
  makes it a tab beside this one, loaded as it is (ported from Search
  `46112d3`)
- Web Inspector is always there, on Chrome's keys: View → Web Inspector
  (⌥⌘I), JavaScript Console (⌥⌘J), Inspect Element (⌥⌘C) — no Settings
  switch any more (ported from Search `d409ad4`)
- No more "can't do that" beep when typing into editors that insert text
  themselves: keys the page didn't use are kept quiet, as in Safari
  (ported from Search `cc8aa58`)
- A download that fails opens the Downloads panel with the reason, instead
  of failing silently — cancellations stay quiet
- Closing a split pane pops it out to the row as a standalone tab instead
  of closing it; the split collapses once one pane is left, keeping
  everything open

## [0.1.2] - 2026-09-24

### Added

- Set Lean as the default browser (Settings → General); links from
  Mail, Slack, PDFs and everywhere else open in the current or a new tab
- Full browser-data import from Chrome, Arc, Dia, Helium, or Safari —
  bookmarks, history, saved passwords decrypted locally from each
  browser's `Login Data` (same PBKDF2 + AES recipe Search uses,
  including Helium's `Helium Storage Key` entry), and extensions where
  each one gets its own permission review before it runs
- Arc sidebar tabs import straight from `StorableSidebar.json`
  (grant the `Arc/` folder itself, not `User Data`)
- Import is merge-only: re-imports and multi-browser imports add
  without duplicating, never overwrite vault passwords or evict your
  history, and already-installed extensions are skipped with a count
- Import failures name the folder scanned, forget bad grants instead
  of retry-looping, point at the real data folder with a ⌘⇧G hint,
  and report gappy history (browser still open) instead of hiding it
- Onboarding import is real end to end — no sample counts, Safari and
  fresh-start handled honestly, passwords wired to the checklist

### Changed

- Onboarding shows exactly once (replayable from Settings → General)
- `README.md` limitations rewritten around what's actually left

## [0.1.0] - 2026-09-20

First public alpha. Everything below shipped in the baseline.

### Tabs

- Horizontal tab strip and collapsible sidebar layouts, drag to reorder
- Pin tabs, split view (two pages side by side, join/separate),
  reopen closed tab, per-tab zoom
- Tab switcher with optional thumbnails; text-only,
  icon-only, and hybrid tab display styles
- Idle tab sleep with configurable timer plus memory-pressure sleep;
  active, loading, media-playing, capturing, dirty-form, and
  cross-origin-frame tabs stay awake; wake restores scroll position
- Session restore across relaunches, pinned tabs included; capped
  local history (200 entries) with search and grouped Settings view

### Address bar and search

- Omnibar matching open tabs, history, and bookmarks as you type;
  floating omnibar, inline URL editing, find-on-page bar
- Six search engines: Google, Bing, DuckDuckGo, Brave, Ecosia, Yahoo

### Interface

- Zen mode (chrome hides, reveals on hover), optional window frame
  with adjustable width, light/dark/system themes
- Interface scale (80–120%), separate Lean UI and webpage typefaces
  with heading/body weight sliders and live preview
- Custom scrollbar styling with native smooth scrolling
- Customizable top bar: back, forward, reload, new tab, extensions,
  downloads, bookmarks, theme, settings — drag between shelves or
  click to show/hide, one-click reset
- Floating picture-in-picture video, system print panel, native
  `alert`/`confirm`/`prompt` and HTTP Basic sign-in dialogs,
  `mailto:`/`tel:`/app-scheme links, per-site camera/mic prompts

### Privacy and blocking

- WebKit content blocking from uBlock Origin lists plus YouTube ad
  coverage, on by default; per-site pause with instant reload
- Review and forget per-site camera/microphone decisions; clear
  history, cookies/site data, and cache independently

### Passwords

- Save/update prompts after successful HTTPS sign-ins, Touch ID
  autofill from the page menu (fields only, never auto-submit),
  full manager: search, reveal, copy, remove, add
- Everything lives in the macOS Keychain; save prompts and
  suggestions toggle separately; CSV import with preview

### Downloads

- Download manager with live progress, custom location, per-file
  save prompts, and file history

### Extensions (macOS 15.4+)

- Install from the Chrome Web Store (link or id, signature-checked)
  or unpacked folders; permission/host review sheet, enable/disable,
  per-extension diagnostics and icons

### System

- Signed in-app updates via Sparkle from GitHub releases
- Custom keyboard shortcuts for navigation and actions
- Guided onboarding tour with browser import, replayable anytime
