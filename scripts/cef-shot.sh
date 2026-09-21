#!/bin/sh
# Headless CEF paint proof: seed one tab, launch Lean Dev, capture the page
# pixels over CDP (Debug-only remote-debugging-port), then quit.
# Usage: scripts/cef-shot.sh [url] [out.png]
set -eu

URL="${1:-https://example.com}"
OUT="${2:-/tmp/cef_shot.png}"
APP="/Applications/Lean Dev.app"
DB="$HOME/Library/Containers/com.dipxsy.lean/Data/Library/Application Support/Lean/Lean.sqlite3"

pkill -x Lean 2>/dev/null || true
pkill -f "Lean Helper" 2>/dev/null || true
sleep 1

sqlite3 "$DB" "INSERT INTO app_state(key,value) VALUES('browserEngineKind','\"cef\"') ON CONFLICT(key) DO UPDATE SET value='\"cef\"';"
ESCAPED_URL="$(printf '%s' "$URL" | sed 's/\\/\\\\/g; s/"/\\"/g')"
sqlite3 "$DB" "INSERT INTO app_state(key,value) VALUES('browserSession_v1','{\"urls\":[\"$ESCAPED_URL\"],\"selectedIndex\":0}') ON CONFLICT(key) DO UPDATE SET value='{\"urls\":[\"$ESCAPED_URL\"],\"selectedIndex\":0}';"

rm -f ~/Library/Containers/com.dipxsy.lean/Data/Library/Application\ Support/Lean/CEF/Singleton*
"$APP/Contents/MacOS/Lean" >/tmp/cef_shot_run.log 2>&1 &
APP_PID=$!

echo "Waiting for CDP port…"
for _ in $(seq 1 30); do
  if curl -s -o /dev/null http://127.0.0.1:9222/json; then
    break
  fi
  sleep 1
done
# Let the page load.
sleep 8
python3 "$(dirname "$0")/cef_shot.py" "$OUT" "$URL" || true
kill $APP_PID 2>/dev/null || true
pkill -f "Lean Helper" 2>/dev/null || true
echo "Screenshot: $OUT"
