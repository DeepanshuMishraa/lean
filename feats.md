# Feature plan

A phased plan for expanding Lean while keeping its native WebKit foundation and avoiding features that depend on unsupported browser APIs.

## Phase 1: settings and browser-data import

Add an **Import Data** category in Settings.

- Read bookmarks and history from a user-selected Chromium profile folder. Also accept a browser bookmark JSON file and a history CSV with `url`, `title`, and optional `timestamp` columns.
- Accept password CSV exports with URL, username, and password columns. Write passwords only to the macOS Keychain; show site/account names in the preview, never password values.
- Preview counts before importing and let users choose bookmarks, history, or both. Password CSV imports have their own confirmation.
- Keep imports local. Read only user-selected files or folders, never alter source data, and report invalid rows and Keychain write failures.
- Show imported bookmarks in Settings with open and remove actions. Merge history into Lean's existing history store, which currently retains up to 200 entries.
- Do not import cookies, open tabs, or encrypted browser password databases in this phase.

## Phase 2: privacy controls

Lean already has global ad/tracker filtering, filter-list refresh, history clearing, and persisted camera/microphone decisions.

- Add a per-site blocking control, accessible from the active tab and Settings. Persist site exceptions and apply them before navigation as well as to already-open pages.
- Add a permissions manager listing sites allowed or denied camera and microphone access, with a way to reset individual sites or all choices.
- Expand data clearing so people can choose history, cookies/site data, and cache separately. Explain that clearing cookies signs them out of sites.
- Keep the existing global blocker and filter update controls.

**Done when:** site exceptions survive relaunch and take effect on the next request; permission choices can be inspected and reset; each data-clearing action affects only its selected data. Add tests for persistence and selection, and verify WebKit data removal on a test profile.

## Phase 3: saved passwords

Add browser-managed credentials stored in the macOS Keychain. Do not store password values in Lean's SQLite database or preferences.

- Offer to save or update a credential after a successful sign-in, with an explicit choice each time.
- Offer matching accounts from the address field or sign-in form, but never fill without a user action.
- Provide a password manager view to search by site, reveal only after macOS user authentication, copy, remove, and add credentials.
- Support importing credentials from a user-selected CSV file. Validate rows and report skipped or invalid entries without exposing passwords in logs.
- Include settings to turn save prompts and sign-in suggestions on or off.

**Done when:** credentials remain in Keychain, site matching is origin-scoped, reveal requires authentication, and save/fill/import flows have tests that do not use real credentials.

**Boundary:** treat passkey creation and automatic system-password autofill as unsupported until verified against the macOS and WebKit APIs Lean can use. Do not imply that this phase adds either capability.

## Phase 4: sleeping tabs

Release WebKit resources held by inactive tabs while preserving enough state to restore them.

- Add an opt-in idle timeout and a manual “Sleep tab” action.
- Preserve the tab's URL, navigation history where available, scroll position, and a preview image; recreate its web view when selected.
- Never sleep the active tab, a pinned tab, a loading page, a page playing audio, a page using camera or microphone, a tab with an active download, or a page with unsaved form input.
- Re-check eligibility before releasing the web view because tab state can change while a snapshot is being captured.
- On memory pressure, shorten the idle timeout or sleep eligible tabs sooner.

**Done when:** a slept tab restores to the right page and approximate scroll position, protected tabs stay awake, and tests cover eligibility changes during sleep.

## Phase 5: extension support investigation and prototype

Explore native WebKit extension support behind an OS availability check before committing to full compatibility.

- Prototype installing, enabling, disabling, reloading, and removing a local unpacked extension.
- Show requested permissions before installation and provide a clear way to revoke them.
- Add an extensions panel and toolbar action menu only after basic lifecycle and permission handling work.
- Clearly report unsupported extension APIs instead of silently claiming compatibility.
- Keep the existing blocker independent of extensions.

**Gate:** confirm the minimum supported macOS version, sandbox behavior, extension lifecycle, and permission APIs with a small prototype. If the required APIs raise Lean's OS floor or cannot work within its sandbox, stop at the prototype and document the limitation.

**Done when:** a minimal test extension loads on supported systems, its permissions can be reviewed and revoked, and unsupported APIs produce actionable errors.

## Suggested order

1. Settings-based import for bookmarks, history, and password CSV exports.
2. Per-site blocking and camera/microphone management.
3. Selective site-data clearing.
4. Keychain-backed password save and fill.
5. Sleeping tabs.
6. Extension prototype, then a separate decision on broader support.
