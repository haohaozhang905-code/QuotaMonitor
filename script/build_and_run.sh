#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="QuotaMonitor"
BINARY_NAME="QuotaMonitor"
BUNDLE_ID="com.cmsjcm.QuotaMonitorStatus"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="/Applications/$APP_NAME.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quotamonitor-build.XXXXXX")"
STAGING_APP="$STAGING_DIR/$APP_NAME.app"
INCOMING_APP="/Applications/.$APP_NAME.app.incoming.$$"
BACKUP_APP="/Applications/.$APP_NAME.app.previous.$$"
LEGACY_DEBUG_APP="$ROOT_DIR/dist/$APP_NAME.app"
LEGACY_RELEASE_APP="$ROOT_DIR/dist/release/$APP_NAME.app"

cleanup() {
  rm -rf "$STAGING_DIR" "$INCOMING_APP"
  if [[ -d "$BACKUP_APP" ]]; then
    if [[ ! -d "$APP_BUNDLE" ]]; then
      mv "$BACKUP_APP" "$APP_BUNDLE"
    else
      rm -rf "$BACKUP_APP"
    fi
  fi
}
trap cleanup EXIT

install_app() {
  rm -rf "$INCOMING_APP" "$BACKUP_APP"
  /usr/bin/ditto "$STAGING_APP" "$INCOMING_APP"
  codesign --verify --deep --strict "$INCOMING_APP"

  pkill -x "$BINARY_NAME" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -x "$BINARY_NAME" >/dev/null 2>&1 || break
    sleep 0.1
  done

  if [[ -d "$APP_BUNDLE" ]]; then
    mv "$APP_BUNDLE" "$BACKUP_APP"
  fi
  if mv "$INCOMING_APP" "$APP_BUNDLE"; then
    rm -rf "$BACKUP_APP"
    rm -rf "$LEGACY_DEBUG_APP" "$LEGACY_RELEASE_APP"
  else
    [[ ! -d "$BACKUP_APP" ]] || mv "$BACKUP_APP" "$APP_BUNDLE"
    return 1
  fi
}

"$ROOT_DIR/script/assemble_app.sh" debug "$STAGING_APP" >/dev/null
install_app

open_app() { /usr/bin/open "$APP_BUNDLE"; }
case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$APP_MACOS/$BINARY_NAME" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == '$BINARY_NAME'" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == '$BUNDLE_ID'" ;;
  --verify|verify) open_app; sleep 2; pgrep -x "$BINARY_NAME" >/dev/null ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
