#!/bin/sh
# Builds Lean and launches it from /Applications so the sandbox permits the
# CEF helper to load the framework. Running straight from DerivedData does
# NOT work: the sandbox blocks the helper's framework load there.
# Usage: scripts/run-cef-dev.sh
set -eu
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
xcodebuild build -scheme Lean -destination 'platform=macOS' 2>&1 | tail -2

SRC="$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/Lean-*/Build/Products/Debug/Lean.app 2>/dev/null | head -1)"
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "No Debug Lean.app found under DerivedData; build first." >&2
  exit 1
fi
DST="/Applications/Lean Dev.app"
rm -rf "$DST"
cp -R "$SRC" "$DST"
echo "Copied to $DST"
open "$DST"
