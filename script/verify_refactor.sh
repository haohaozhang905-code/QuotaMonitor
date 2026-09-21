#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_config.sh"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quotamonitor-verify.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT

export CLANG_MODULE_CACHE_PATH="$VERIFY_DIR/clang-modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$VERIFY_DIR/swiftpm-modules"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

cd "$ROOT_DIR"
echo "== Swift tests (isolated caches) =="
swift test --disable-sandbox --scratch-path "$VERIFY_DIR/build"

echo "== App build =="
swift build --disable-sandbox --scratch-path "$VERIFY_DIR/build"

echo "== Localization key parity =="
ruby -e '
  require "set"
  files = ARGV
  values = files.map do |path|
    File.read(path).scan(/^\s*"((?:\\.|[^"\\])+)"\s*=/).flatten.to_set
  end
  missing = values[0] - values[1]
  extra = values[1] - values[0]
  abort "missing English keys: #{missing.to_a.sort.join(", ")}" unless missing.empty?
  abort "missing Simplified Chinese keys: #{extra.to_a.sort.join(", ")}" unless extra.empty?
  puts "localization keys match (#{values[0].length})"
' Sources/QuotaMonitor/Resources/en.lproj/Localizable.strings Sources/QuotaMonitor/Resources/zh-Hans.lproj/Localizable.strings

if rg -n --no-messages '\.autosaveName\s*=' Sources/QuotaMonitor/App/QuotaMonitorApp.swift; then
  echo "verification failed: custom status item autosaveName is prohibited" >&2
  exit 1
fi
if ! rg -q 'QUOTAMONITOR_BUNDLE_ID="com\.cmsjcm\.QuotaMonitorStatus4"' script/app_config.sh; then
  echo "verification failed: Status4 bundle identity changed unexpectedly" >&2
  exit 1
fi

echo "== Diff whitespace check =="
git diff --check

echo "== Security and status-item source guard =="
bash script/security_check.sh

echo "== Code-size and duplicate-block report =="
ruby script/code_metrics.rb

if [[ "${1:-}" == "--runtime" ]]; then
  app_pid="$(pgrep -x "$QUOTAMONITOR_BINARY_NAME" | head -n 1)"
  [[ -n "$app_pid" ]] || { echo "runtime verification failed: app is not running" >&2; exit 1; }
  bash script/verify_menu_bar_status.sh "$app_pid" "$QUOTAMONITOR_BUNDLE_ID"
fi

echo "refactor verification: passed"
