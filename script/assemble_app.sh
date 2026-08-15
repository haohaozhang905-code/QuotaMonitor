#!/usr/bin/env bash
set -eo pipefail

CONFIGURATION="${1:-debug}"
APP_NAME="QuotaMonitor"
BINARY_NAME="QuotaMonitor"
# macOS 26 Control Center keeps a separate per-bundle menu-bar ledger. The
# previous bundle identity was left permanently blocked on this machine, so
# use a fresh identity while retaining the app's existing data directories.
BUNDLE_ID="com.cmsjcm.QuotaMonitorStatus"
VERSION="${QUOTAMONITOR_VERSION:-0.1.8}"
BUILD_NUMBER="${QUOTAMONITOR_BUILD_NUMBER:-10}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${2:-}"
if [[ -z "$APP_BUNDLE" || "$(basename "$APP_BUNDLE")" != "$APP_NAME.app" ]]; then
  echo "usage: $0 [debug|release] /explicit/path/$APP_NAME.app" >&2
  exit 2
fi
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
APP_RESOURCES="$APP_BUNDLE/Contents/Resources"

case "$CONFIGURATION" in
  debug) SWIFT_CONFIGURATION="debug" ;;
  release) SWIFT_CONFIGURATION="release" ;;
  *) echo "usage: $0 [debug|release] [output.app]" >&2; exit 2 ;;
esac

cd "$ROOT_DIR"
# Allow environment-specific build flags (e.g. --disable-sandbox on hosts where
# SwiftPM's sandbox-exec is rejected by the system). Opt-in, no behavior change
# on standard macOS developer machines.
EXTRA_BUILD_ARGS=()
if [[ -n "${SWIFT_BUILD_EXTRA_ARGS:-}" ]]; then
  read -ra EXTRA_BUILD_ARGS <<< "$SWIFT_BUILD_EXTRA_ARGS"
fi

BUILD_ARGS=("${EXTRA_BUILD_ARGS[@]}")
if [[ "$SWIFT_CONFIGURATION" == "release" ]]; then
  BUILD_ARGS+=(-c release --arch arm64 --arch x86_64)
fi

swift build --disable-sandbox "${BUILD_ARGS[@]}"
BIN_PATH="$(swift build --disable-sandbox "${BUILD_ARGS[@]}" --show-bin-path)"
SWIFT_BINARY_NAME="QuotaMonitor"
BUILD_BINARY="$BIN_PATH/$SWIFT_BINARY_NAME"
RESOURCE_BUNDLE="$(find "$BIN_PATH" -maxdepth 1 -type d -name 'QuotaMonitor_QuotaMonitor.bundle' -print -quit)"
ICON_SOURCE="$ROOT_DIR/Sources/QuotaMonitor/Resources/AppIcon.icns"

[[ -x "$BUILD_BINARY" ]] || { echo "missing executable: $BUILD_BINARY" >&2; exit 3; }
[[ -f "$ICON_SOURCE" ]] || { echo "missing app icon: $ICON_SOURCE" >&2; exit 3; }
# --- Assemble host app bundle ---
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_MACOS/$BINARY_NAME"
chmod +x "$APP_MACOS/$BINARY_NAME"
cp "$ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundleExecutable</key><string>$BINARY_NAME</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

# --- Resolve signing identity ---
SIGNING_IDENTITY="${QUOTAMONITOR_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ "$CONFIGURATION" == "release" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
      | head -n 1)"
  else
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' \
      | head -n 1)"
  fi
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ "${QUOTAMONITOR_ALLOW_ADHOC:-0}" == "1" ]]; then
    SIGNING_IDENTITY="-"
    echo "warning: assembling an ad-hoc signed build; it is not suitable for public distribution" >&2
  else
    echo "No suitable signing identity found." >&2
    if [[ "$CONFIGURATION" == "release" ]]; then
      echo "Install a Developer ID Application certificate, or set QUOTAMONITOR_ALLOW_ADHOC=1 for local packaging QA only." >&2
    else
      echo "Install an Apple Development certificate, or set QUOTAMONITOR_ALLOW_ADHOC=1." >&2
    fi
    exit 4
  fi
fi

# --- Sign the host bundle. ---
HOST_ENTITLEMENTS="$ROOT_DIR/Sources/QuotaMonitor/QuotaMonitor.entitlements"
APP_SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY" --entitlements "$HOST_ENTITLEMENTS" --identifier "$BUNDLE_ID")
if [[ "$CONFIGURATION" == "release" && "$SIGNING_IDENTITY" != "-" ]]; then
  APP_SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${APP_SIGN_ARGS[@]}" "$APP_BUNDLE"

# --- App signature verification ---
echo "--- complete app signature ---"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "$APP_BUNDLE"
