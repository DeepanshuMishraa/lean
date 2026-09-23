# Feature plan

A phased plan for expanding Lean while keeping its native WebKit foundation and avoiding features that depend on unsupported browser APIs.

## Phase 1: settings and browser-data import

Add an **Import Data** category in Settings.

- Offer Chromium browsers, including Helium, as source choices. On first import, request access to the selected browser's data folder, remember that access, and discover its profiles automatically. Also accept a browser bookmark JSON file and a history CSV with `url`, `title`, and optional `timestamp` columns.
- Accept password CSV exports with URL, username, and password columns. Write passwords only to the macOS Keychain; show site/account names in the preview, never password values.
- Preview counts before importing and let users choose bookmarks, history, or both. Password CSV imports have their own confirmation.
- Keep imports local. Read only user-selected browser folders or files, never alter source data, snapshot Chromium history databases so browsers can remain open, and report invalid rows and Keychain write failures. Settings action buttons inherit Lean's configured UI font.
- Show imported bookmarks in Settings with open and remove actions. Merge history into Lean's existing history store, which currently retains up to 200 entries.
- Do not import cookies, open tabs, or encrypted browser password databases in this phase.

## Phase 2: privacy controls

Implemented in Settings:

- Pause blocking for the selected hostname, manage paused sites, and apply the choice before main-frame navigation and to existing tabs. Exceptions match the exact hostname.
- Review saved camera/microphone decisions by site and forget one site's choices or all choices.
- Clear Lean's recorded history, cookies and site storage, or WebKit caches separately. Cookie/site-data clearing signs the user out.
- Keep the global blocker and filter-list refresh controls.

**Verification:** policy and permission-store tests pass. Manually verify actual WebKit data removal and per-site blocking in the app before release.

## Phase 3: saved passwords

Implemented:

- Save/update prompts after a submitted HTTPS sign-in navigates successfully, with an explicit choice. Passwords stay in the macOS Keychain, never Lean's SQLite or preferences.
- Offer matching accounts from the HTTPS page context menu. Filling requires macOS authentication and an explicit account selection; Lean fills fields only and never submits the form.
- Add a Passwords Settings category to search, reveal after authentication, copy, remove, or add sign-ins. Save prompts and page-menu suggestions can be disabled separately.
- Keep CSV import user-selected; preserve exact scheme/host/port matching and show site/account names, never password values.

**Verification:** origin matching and CSV parsing have tests that use no real credentials. Manually verify Keychain authentication, save prompts, and filling on a test profile before release.

**Boundary:** passkey creation and automatic system-password autofill remain unsupported; this phase does not claim either capability.

## Phase 4: sleeping tabs

Implemented:

- Add opt-in idle sleep (5, 15, 30, or 60 minutes), a manual action in inactive-tab menus, and eligible-tab sleep attempts during memory pressure.
- Release inactive WebKit views while keeping the URL, preview image, and approximate scroll position. Selecting a sleeping tab recreates its view and reloads the URL.
- Keep active/loading tabs, downloads, camera/microphone capture, playing media/Web Audio, unsaved form input, and pages with cross-origin or sandboxed iframes awake.
- Re-check eligibility before and after the asynchronous snapshot so recent input or playback prevents release.

**Limitations:** Sleeping tabs retain WebKit's opaque `interactionState` in memory and restore it into a recreated view; if WebKit provides no state, wake falls back to reloading the URL and restoring scroll. Cross-origin frames are conservatively kept awake. Lean has no pinned-tab feature.

**Verification:** policy tests cover protected activity and an eligibility change before release. Manually verify sleep/wake, scroll restoration, and memory pressure behavior before release.

## Phase 5: extension support

**Implemented first slice:** WebKit extension support is gated to macOS 15.4+, preserving Lean's macOS 14 minimum. Settings can install verified Chrome Web Store extensions from a URL or ID and load unpacked local extensions, review and selectively grant required/optional permissions and site access, enable, reload, remove, and read initial diagnostics. Lean copies extensions into app-controlled storage, persists the installed list and grants, and attaches the shared WebKit extension controller to tab configurations. Store packages are signature-checked against their extension IDs before unpacking. A focused lifecycle test covers load, unload, reload, and permission revocation.

**Limitations:** extension toolbar popups and browser tab/window integrations are not wired up. Optional runtime permission requests are denied until granted in Settings. Diagnostics currently show parse/load errors, not a live error stream. Verify folder access and content injection manually under the sandbox before release; keep support availability-gated and do not raise Lean's overall OS floor.

## Suggested order

1. Settings-based import for bookmarks, history, and password CSV exports.
2. Per-site blocking and camera/microphone management.
3. Selective site-data clearing.
4. Keychain-backed password save and fill.
5. Sleeping tabs.
6. WebKit-gated extension installation and permission controls, then toolbar and tab API integration.
