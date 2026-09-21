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
HELPER_ENTITLEMENTS="${SRCROOT}/Lean/Helper/LeanHelper.entitlements"
sign_helper() {
  # Enforce inherit-only entitlements: Xcode may inject Debug extras
  # (get-task-allow, testmanagerd) that break sandbox inheritance and kill
  # every CEF child process. Re-sign ad-hoc with exactly our two keys.
  if [ -f "$HELPER_ENTITLEMENTS" ]; then
    /usr/bin/codesign --force --sign - --timestamp=none \
      --entitlements "$HELPER_ENTITLEMENTS" \
      "$1" || true
  fi
}
if [ -d "$HELPER_SRC" ]; then
  rm -rf "$HELPER_DST"
  cp -R "$HELPER_SRC" "$HELPER_DST"
  sign_helper "$HELPER_DST"

  # Chromium on macOS does NOT run every child type from
  # browser_subprocess_path: renderers, the GPU process, and the macOS
  # notification provider each demand a sibling bundle named
  # "Lean Helper (<Variant>).app" next to the base helper. A missing
  # Renderer variant fails every page load (TS_LAUNCH_FAILED → blank page),
  # so clone the base helper per variant with a patched Info.plist.
  for variant in Renderer GPU Alerts; do
    case "$variant" in
      Renderer) SUFFIX="renderer" ;;
      GPU) SUFFIX="gpu" ;;
      Alerts) SUFFIX="alerts" ;;
    esac
    VARIANT_NAME="Lean Helper ($variant).app"
    VARIANT_DST="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/$VARIANT_NAME"
    rm -rf "$VARIANT_DST"
    cp -R "$HELPER_DST" "$VARIANT_DST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Lean Helper ($variant)" \
      "$VARIANT_DST/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Lean Helper ($variant)" \
      "$VARIANT_DST/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.dipxsy.lean.helper.$SUFFIX" \
      "$VARIANT_DST/Contents/Info.plist"
    mv "$VARIANT_DST/Contents/MacOS/Lean Helper" \
      "$VARIANT_DST/Contents/MacOS/Lean Helper ($variant)"
    sign_helper "$VARIANT_DST"
  done
fi
