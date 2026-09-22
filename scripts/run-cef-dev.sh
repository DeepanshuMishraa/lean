#!/bin/sh
# Builds Lean and launches it from /Applications so the sandbox permits the
# CEF helper to load the framework. Running straight from DerivedData does
# NOT work: the sandbox blocks the helper's framework load there.
# Usage: scripts/run-cef-dev.sh
set -eu
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
BUILD_LOG="$(mktemp -t lean-cef-build.XXXXXX)"
if ! xcodebuild build -scheme Lean -destination 'platform=macOS' >"$BUILD_LOG" 2>&1; then
  tail -20 "$BUILD_LOG"
  echo "xcodebuild failed; full log: $BUILD_LOG" >&2
  exit 1
fi
tail -2 "$BUILD_LOG"
rm -f "$BUILD_LOG"

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
