# CEF opt-in engine (macOS) — IMPLEMENTED

Default stays WebKit. CEF is opt-in via Settings → Browsing → Rendering Engine.
Switching shows a restart dialog; on relaunch every tab uses the new engine —
a process never mixes engines. Status: initializes in the sandboxed app,
spawns helpers, navigates, completes loads. Verified headless
(init + helper procs + history-recorded loads); needs a visual pass on a real
display for paint/input/scroll feel.

## Layout

- `Lean/CEFBridge/` — ObjC++ bridge. `CEFManager` (init/pump, single-threaded
  `CefDoMessageLoopWork` pump at 60Hz), `CEFBrowserHost` (one windowed browser
  per tab: nav state, dialogs, auth, media perms, downloads, popups, find,
  zoom). Headers stay pure ObjC; C++ never leaks into Swift.
- `Lean/CEF/` — `CEFBootstrap` (one-time init + paths), `CEFEngineView`
  (returns the tab-owned container view so tab switches re-insert it).
- `Lean/Helper/` — subprocess entry (`CefExecuteProcess`), own Info.plist,
  inherit-only entitlements.
- `LeanTab` carries `engineKind` + `cefHost`; nav/find/zoom/download methods
  branch. No live tab ever hot-swaps engines.
- `vendor/cef` (gitignored, `scripts/fetch-cef.sh`, pinned 152.0.8 arm64
  minimal) compiles `libcef_dll` + bridge in-target; missing dir = WebKit-only
  build that still compiles and runs.

## Hard-won requirements (all load-bearing)

1. **Load the library explicitly.** Every wrapper call routes through function
   pointers filled only by `cef_load_library` (`CefScopedLibraryLoader::LoadInMain`).
   Without it the first `CefString` assignment jumps to NULL. (The framework
   being dyld-loaded is NOT enough.)
2. **`CefExecuteProcess` before `CefInitialize`** in the browser process.
3. **`settings.size = sizeof(settings)`**, plus `root_cache_path`.
4. **Single-threaded loop + external pump.** `multi_threaded_message_loop=true`
   fails init under App Sandbox; pump `CefDoMessageLoopWork()` on a main-thread
   timer instead.
5. **App-group entitlement for the Mach rendezvous.** Chromium registers
   `<bundle-id>.MachPortRendezvousServer.<pid>` at init; the sandbox denies
   `bootstrap_check_in` otherwise and init fails (FATAL single-threaded,
   silent false multi-threaded). `application-groups: [com.dipxsy.lean]`
   suffices ad-hoc; production wants a TeamID-prefixed group (paid Developer ID).
6. **Helpers: sandbox + `inherit` ONLY — enforced at signing.** Any other
  key (including Xcode's auto-injected Debug extras like `get-task-allow` /
  `testmanagerd`) breaks inheritance and every child dies instantly
  (GPU/network/renderer, exit 5, then FATAL "GPU process isn't usable").
  `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` plus a forced re-sign in
  `embed-cef.sh` keep the helper signature to exactly the two keys.
7. **`--disable-gpu-sandbox`** on the browser command line: the GPU process
   cannot nest Chromium's sandbox inside ours (still inherits App Sandbox).
8. **Versioned framework layout.** CEF ships flat; Xcode validation demands
   `Versions/A` + `Current` symlink ladder (`scripts/embed-cef.sh` reshapes
   the copy, then ad-hoc signs it).
9. **Never launch CEF from DerivedData.** The sandbox blocks the helper's
   framework load there. Copy to /Applications first:
   `scripts/run-cef-dev.sh` (build → copy → open).

## Deliberate v1 gaps

- Popups cancel into plain new tabs (no `window.opener` handshake); `window.close()` closes the tab.
- No per-tab CEF snapshot for the tab switcher (falls back to icon/title).
- Find has no result counts; dismissing the find bar doesn't `StopFinding`.
- No `CefShutdown` on quit (pump stops; process exit reaps helpers).
- ContentBlocker rules don't apply to CEF (needs a `CefRequestHandler` port).
- CEF tabs always create an idle WKWebView alongside (TODO: make lazy).
- Extensions: CEF exposes only a subset — full extensions need a Chromium fork.
- Apple Pay / iCloud Passwords stay Safari-only on any engine.
