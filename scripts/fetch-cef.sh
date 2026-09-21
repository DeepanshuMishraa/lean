#!/bin/sh
# Fetches the pinned CEF minimal distribution for macOS into vendor/cef/.
# The framework (~350MB) is intentionally gitignored, never committed.
# Usage: scripts/fetch-cef.sh [--arch arm64|x86_64]
set -eu

ARCH="${1:-}"; [ "${ARCH:-}" = "" ] && ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) CEF_ARCH="macosarm64" ;;
  x86_64) CEF_ARCH="macosx64" ;;
  *) echo "usage: $0 [--arch arm64|x86_64]" >&2; exit 1 ;;
esac
if [ "${1:-}" = "--arch" ]; then :; fi

CEF_VERSION="152.0.8+g1ce985c+chromium-152.0.7977.134"
# Pinned sha1 is for the arm64 minimal tarball. x86_64 needs its own pin
# (see https://cef-builds.spotifycdn.com/index.html) before release builds.
CEF_SHA1="3e989a2f69f7288191e63f19bf303d9256779a94"
if [ "$CEF_ARCH" != "macosarm64" ]; then
  echo "Only macosarm64 is pinned so far; add the ${CEF_ARCH} sha1 first." >&2
  exit 1
fi
CEF_NAME="cef_binary_${CEF_VERSION}_${CEF_ARCH}_minimal"
TARBALL="vendor/${CEF_NAME}.tar.bz2"
URL="https://cef-builds.spotifycdn.com/${CEF_NAME}.tar.bz2"

cd "$(dirname "$0")/.."
mkdir -p vendor

if [ -d vendor/cef ] && grep -q "^${CEF_VERSION} ${CEF_ARCH} minimal" vendor/cef/VERSION.txt 2>/dev/null; then
  echo "vendor/cef already at ${CEF_VERSION} (${CEF_ARCH}); nothing to do."
  exit 0
fi

echo "Downloading ${URL} ..."
curl -sSL --fail -o "$TARBALL" "$URL"

echo "Verifying sha1 ..."
ACTUAL="$(shasum "$TARBALL" | awk '{print $1}')"
if [ "$ACTUAL" != "$CEF_SHA1" ]; then
  echo "sha1 mismatch: expected ${CEF_SHA1}, got ${ACTUAL}" >&2
  exit 1
fi

echo "Extracting ..."
rm -rf vendor/cef
mkdir -p vendor/cef-tmp
tar -xjf "$TARBALL" -C vendor/cef-tmp
mv "vendor/cef-tmp/${CEF_NAME}" vendor/cef
rmdir vendor/cef-tmp
rm "$TARBALL"
echo "${CEF_VERSION} ${CEF_ARCH} minimal" > vendor/cef/VERSION.txt
echo "Done: vendor/cef ($(du -sh vendor/cef | awk '{print $1}'))"
