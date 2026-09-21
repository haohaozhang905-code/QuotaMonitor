#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_config.sh"
APP_NAME="$QUOTAMONITOR_APP_NAME"
BINARY_NAME="$QUOTAMONITOR_BINARY_NAME"
# 与 assemble_app.sh 保持一致。本机 macOS 26.6 的 Status3 在 2026-09-13
# 再次被 Control Center 屏蔽，且系统没有公开 API 可在应用内恢复。
BUNDLE_ID="$QUOTAMONITOR_BUNDLE_ID"
PREVIOUS_BUNDLE_ID="$QUOTAMONITOR_PREVIOUS_BUNDLE_ID"
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

migrate_local_defaults_if_needed() {
  if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    return
  fi
  if ! defaults read "$PREVIOUS_BUNDLE_ID" >/dev/null 2>&1; then
    return
  fi

  local defaults_snapshot="$STAGING_DIR/previous-defaults.plist"
  defaults export "$PREVIOUS_BUNDLE_ID" "$defaults_snapshot" >/dev/null
  defaults import "$BUNDLE_ID" "$defaults_snapshot" >/dev/null
  # 登录项属于应用身份，不能把“已初始化”标记迁移到新 Bundle ID，
  # 否则新应用会误以为已注册，实际却不会登录后自启。
  defaults delete "$BUNDLE_ID" "QuotaMonitor.launchAtLoginInitialized" >/dev/null 2>&1 || true
  echo "migrated local preferences: $PREVIOUS_BUNDLE_ID -> $BUNDLE_ID"
}

"$ROOT_DIR/script/assemble_app.sh" debug "$STAGING_APP" >/dev/null
install_app
migrate_local_defaults_if_needed

open_app() { /usr/bin/open "$APP_BUNDLE"; }
verify_runtime() {
  sleep 2
  local app_pid
  app_pid="$(pgrep -x "$BINARY_NAME" | head -n 1)"
  [[ -n "$app_pid" ]] || { echo "runtime verification failed: $BINARY_NAME is not running" >&2; return 1; }
  "$ROOT_DIR/script/verify_menu_bar_status.sh" "$app_pid" "$BUNDLE_ID"
}
case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$APP_MACOS/$BINARY_NAME" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == '$BINARY_NAME'" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == '$BUNDLE_ID'" ;;
  --verify|verify) open_app; verify_runtime ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
