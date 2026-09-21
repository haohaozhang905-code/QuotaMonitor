#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mapfile_compat() {
  while IFS= read -r line; do
    [[ -n "$line" ]] && AUDIT_FILES+=("$line")
  done
}

AUDIT_FILES=()
mapfile_compat < <(git ls-files --cached --others --exclude-standard)

if [[ ${#AUDIT_FILES[@]} -eq 0 ]]; then
  echo "security audit: no publishable files found" >&2
  exit 1
fi

for file in "${AUDIT_FILES[@]}"; do
  case "/$file" in
    */.env|*/.env.*|*/auth.json|*/.credentials.json|*.p8|*.p12|*.pem|*.key|*.mobileprovision|*.provisionprofile)
      echo "security audit: blocked sensitive file: $file" >&2
      exit 1
      ;;
  esac
done

SCAN_FILES=()
for file in "${AUDIT_FILES[@]}"; do
  [[ "$file" == "script/security_check.sh" ]] && continue
  SCAN_FILES+=("$file")
done

if rg -n --no-messages \
  -e '/Users/' \
  -e '(gmail|icloud|outlook|protonmail|qq)\.com' \
  -e 'sk-(proj-|ant-)?[A-Za-z0-9_-]{16,}' \
  -e 'github_pat_[A-Za-z0-9_]+' \
  -e 'gh[opsu]_[A-Za-z0-9]{20,}' \
  -e 'AKIA[0-9A-Z]{16}' \
  -e 'xox[baprs]-[A-Za-z0-9-]+' \
  -e 'BEGIN ([A-Z ]+)?PRIVATE KEY' \
  -e 'eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}' \
  "${SCAN_FILES[@]}"; then
  echo "security audit: possible secret or personal data found" >&2
  exit 1
fi

# macOS 26 会记住 NSStatusItem.autosaveName 的 blocked 状态，导致进程正常但
# 菜单栏入口永久消失。把这个已复现过的回归变成发布前硬失败。
if rg -n --no-messages '\.autosaveName\s*=' Sources/QuotaMonitor/App/QuotaMonitorApp.swift; then
  echo "security audit: NSStatusItem autosaveName can persist a blocked menu-bar item" >&2
  exit 1
fi

if rg -n --no-messages 'BUNDLE_ID="com\.cmsjcm\.QuotaMonitor' script/assemble_app.sh script/build_and_run.sh script/package_release.sh; then
  echo "security audit: bundle identity must come from script/app_config.sh" >&2
  exit 1
fi
if ! rg -q 'QUOTAMONITOR_BUNDLE_ID="com\.cmsjcm\.QuotaMonitorStatus4"' script/app_config.sh; then
  echo "security audit: expected Status4 bundle identity is missing" >&2
  exit 1
fi

echo "security audit: passed (${#AUDIT_FILES[@]} publishable files checked)"
