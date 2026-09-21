#!/usr/bin/env bash
set -euo pipefail

APP_PID="${1:-}"
BUNDLE_ID="${2:-}"

if [[ -z "$APP_PID" || -z "$BUNDLE_ID" ]]; then
  echo "usage: $0 app-pid bundle-id" >&2
  exit 2
fi

STATUS_LOG="$(/usr/bin/log show --last 2m --style compact \
  --predicate 'subsystem == "com.apple.controlcenter" AND category == "appStatusItems"')"
PID_SUFFIX="-$APP_PID)"

if ! printf '%s\n' "$STATUS_LOG" \
  | grep -F "$BUNDLE_ID" \
  | grep -F -- "$PID_SUFFIX" \
  | grep -F "Host properties initialized" >/dev/null; then
  echo "menu-bar verification failed: Control Center did not initialize the status item for pid $APP_PID" >&2
  exit 1
fi

if printf '%s\n' "$STATUS_LOG" \
  | grep -F "$BUNDLE_ID" \
  | grep -F -- "$PID_SUFFIX" \
  | grep -F "Moving host to blocked list" >/dev/null; then
  echo "menu-bar verification failed: Control Center moved the status item to the blocked list" >&2
  exit 1
fi

echo "menu-bar verification: status item initialized and not blocked (pid $APP_PID)"
