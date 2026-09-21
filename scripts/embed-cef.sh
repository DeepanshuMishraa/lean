#!/bin/sh
# Embeds the CEF framework and Lean Helper into the built app bundle.
# Runs as an Xcode post-build script; safe no-op when vendor/cef is absent
# (fresh clones can still build and run on WebKit).
set -eu

FW_SRC="${SRCROOT}/vendor/cef/Release/Chromium Embedded Framework.framework"
FW_DST="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/Chromium Embedded Framework.framework"
if [ -d "$FW_SRC" ]; then
  rm -rf "$FW_DST"
  cp -R "$FW_SRC" "$FW_DST"
  # CEF ships a flat framework (binary + Resources/ + Libraries/ at top).
  # macOS tooling expects the versioned layout, so reshape the COPY:
  #   Versions/A/{binary,Resources,Libraries} + Current/symlink ladder.
  FW_BASENAME="Chromium Embedded Framework"
  FW_VER="$FW_DST/Versions/A"
  mkdir -p "$FW_VER"
  # shellcheck disable=SC2012
  for entry in "$FW_DST"/*; do
    case "$entry" in
      */Versions) continue ;;
      *) mv "$entry" "$FW_VER/" ;;
    esac
  done
  ln -sfn "A" "$FW_DST/Versions/Current"
  ln -sfn "Versions/Current/$FW_BASENAME" "$FW_DST/$FW_BASENAME"
  ln -sfn "Versions/Current/Resources" "$FW_DST/Resources"
  if [ -d "$FW_VER/Libraries" ]; then
    ln -sfn "Versions/Current/Libraries" "$FW_DST/Libraries"
  fi
  # Ad-hoc sign so the hardened runtime accepts it without a Team ID.
  /usr/bin/codesign --force --sign - --timestamp=none "$FW_DST" || true
fi

HELPER_SRC="${BUILT_PRODUCTS_DIR}/Lean Helper.app"
HELPER_DST="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/Lean Helper.app"
if [ -d "$HELPER_SRC" ]; then
  rm -rf "$HELPER_DST"
  cp -R "$HELPER_SRC" "$HELPER_DST"
  # Enforce inherit-only entitlements: Xcode may inject Debug extras
  # (get-task-allow, testmanagerd) that break sandbox inheritance and kill
  # every CEF child process. Re-sign ad-hoc with exactly our two keys.
  if [ -f "${SRCROOT}/Lean/Helper/LeanHelper.entitlements" ]; then
    /usr/bin/codesign --force --sign - --timestamp=none \
      --entitlements "${SRCROOT}/Lean/Helper/LeanHelper.entitlements" \
      "$HELPER_DST" || true
  fi
fi
