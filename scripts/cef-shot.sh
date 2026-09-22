#!/bin/sh
# Headless CEF paint proof: seed one tab, launch Lean Dev, capture the page
# pixels over CDP (Debug-only remote-debugging-port), then quit.
# Usage: scripts/cef-shot.sh [url] [out.png]
set -eu

URL="${1:-https://example.com}"
OUT="${2:-/tmp/cef_shot.png}"
APP="/Applications/Lean Dev.app"
DB="$HOME/Library/Containers/com.dipxsy.lean/Data/Library/Application Support/Lean/Lean.sqlite3"

# Pick a free CDP port so an unrelated localhost:9222 can't satisfy readiness.
CDP_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
export LEAN_CEF_CDP_PORT="$CDP_PORT"
export LEAN_CEF_DEBUG=1

pkill -x Lean 2>/dev/null || true
pkill -f "Lean Helper" 2>/dev/null || true
sleep 1

# Snapshot the user's state keys so we can restore them on exit (trap).
BACKUP_DIR="$(mktemp -d -t lean-cef-shot.XXXXXX)"
cleanup() {
  # Restore caller's tabs + engine, then quit the instance we launched.
  if [ -f "$BACKUP_DIR/engine.bak" ]; then
    ENG="$(cat "$BACKUP_DIR/engine.bak")"
    python3 - "$DB" "$ENG" <<'EOF'
import sqlite3, sys
db, eng = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
if eng == "__ABSENT__":
    con.execute("DELETE FROM app_state WHERE key='browserEngineKind'")
else:
    con.execute("INSERT INTO app_state(key,value) VALUES('browserEngineKind',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (eng,))
con.commit()
EOF
  fi
  if [ -f "$BACKUP_DIR/session.bak" ]; then
    SES="$(cat "$BACKUP_DIR/session.bak")"
    python3 - "$DB" "$SES" <<'EOF'
import sqlite3, sys
db, ses = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
if ses == "__ABSENT__":
    con.execute("DELETE FROM app_state WHERE key='browserSession_v1'")
else:
    con.execute("INSERT INTO app_state(key,value) VALUES('browserSession_v1',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (ses,))
con.commit()
EOF
  fi
  rm -rf "$BACKUP_DIR"
  if [ -n "${APP_PID:-}" ]; then
    kill "$APP_PID" 2>/dev/null || true
  fi
  pkill -f "Lean Helper" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Snapshot current values (may be absent) before overwriting.
python3 - "$DB" "$BACKUP_DIR" <<'EOF'
import os, sqlite3, sys
db, d = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
for key, name in (("browserEngineKind", "engine.bak"), ("browserSession_v1", "session.bak")):
    row = con.execute("SELECT value FROM app_state WHERE key=?", (key,)).fetchone()
    open(os.path.join(d, name), "w").write(row[0] if row else "__ABSENT__")
EOF

# Seed state with bound parameters (URLs with quotes stay valid JSON/SQL).
python3 - "$DB" "$URL" <<'EOF'
import json, sqlite3, sys
db, url = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
con.execute("INSERT INTO app_state(key,value) VALUES('browserEngineKind','\"cef\"') ON CONFLICT(key) DO UPDATE SET value='\"cef\"'")
session = json.dumps({"urls": [url], "selectedIndex": 0})
con.execute("INSERT INTO app_state(key,value) VALUES('browserSession_v1',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (session,))
con.commit()
EOF

rm -f ~/Library/Containers/com.dipxsy.lean/Data/Library/Application\ Support/Lean/CEF/Singleton*
"$APP/Contents/MacOS/Lean" >/tmp/cef_shot_run.log 2>&1 &
APP_PID=$!

echo "Waiting for CDP port $CDP_PORT…"
READY=0
for _ in $(seq 1 30); do
  if curl -s -o /dev/null "http://127.0.0.1:$CDP_PORT/json"; then
    READY=1
    break
  fi
  # Bail early if our instance already exited.
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "Lean exited before CDP appeared; see /tmp/cef_shot_run.log" >&2
    exit 1
  fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then
  echo "Timed out waiting for CDP on $CDP_PORT; see /tmp/cef_shot_run.log" >&2
  exit 1
fi
# Let the page load.
sleep 8
# Capture the sole seeded page without filtering by the pre-navigation URL:
# redirects/canonicalization change the final URL, so a substring match can
# select nothing even though the page loaded.
python3 "$(dirname "$0")/cef_shot.py" "$OUT" "$CDP_PORT"
echo "Screenshot: $OUT"
