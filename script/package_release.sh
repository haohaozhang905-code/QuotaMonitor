#!/usr/bin/env bash
set -euo pipefail

MODE="notarized"
if [[ "${1:-}" == "--unsigned" ]]; then
  MODE="unsigned"
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--unsigned]" >&2
  exit 2
fi

APP_NAME="QuotaMonitor"
VERSION="${QUOTAMONITOR_VERSION:-0.1.8}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
STAGING_DIR="$DIST_DIR/dmg-root"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION.zip"

cleanup() {
  rm -rf "$STAGING_DIR" "$ZIP_PATH" "$APP_BUNDLE"
}
trap cleanup EXIT

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

if [[ "$MODE" == "notarized" ]]; then
  : "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to a notarytool keychain profile. See docs/RELEASING.md.}"
  "$ROOT_DIR/script/assemble_app.sh" release "$APP_BUNDLE" >/dev/null

  ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
else
  QUOTAMONITOR_ALLOW_ADHOC=1 QUOTAMONITOR_SIGNING_IDENTITY=- \
    "$ROOT_DIR/script/assemble_app.sh" release "$APP_BUNDLE" >/dev/null
  DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-UNSIGNED.dmg"
fi

mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

if [[ "$MODE" == "notarized" ]]; then
  SIGNING_IDENTITY="${QUOTAMONITOR_SIGNING_IDENTITY:-}"
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
      | head -n 1)"
  fi
  [[ -n "$SIGNING_IDENTITY" ]] || { echo "Developer ID Application certificate not found." >&2; exit 4; }

  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
fi

cleanup
shasum -a 256 "$DMG_PATH"
echo "$DMG_PATH"
