#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  "AGENTS.md"
  "docs/PRODUCT.md"
  "docs/DESIGN_SYSTEM.md"
  "docs/TRACEABILITY.md"
  "docs/engineering/AI_COLLABORATION.md"
  "docs/decisions/README.md"
  "specs/README.md"
  "specs/_template/spec.md"
  "specs/_template/plan.md"
  "specs/_template/tasks.md"
  "specs/_template/acceptance.md"
  "specs/001-reminder-v1.1/spec.md"
  "specs/001-reminder-v1.1/plan.md"
  "specs/001-reminder-v1.1/tasks.md"
  "specs/001-reminder-v1.1/acceptance.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -s "$file" ]]; then
    echo "SDD verification failed: missing or empty $file" >&2
    exit 1
  fi
done

spec_file="specs/001-reminder-v1.1/spec.md"
plan_file="specs/001-reminder-v1.1/plan.md"
trace_file="docs/TRACEABILITY.md"

for link_target in 'docs/DESIGN_SYSTEM.md' 'specs/001-reminder-v1.1/spec.md'; do
  if ! rg -q --fixed-strings "$link_target" README.md; then
    echo "SDD verification failed: README missing link to $link_target" >&2
    exit 1
  fi
done

if ! rg -q --fixed-strings 'docs/DESIGN_SYSTEM.md' AGENTS.md; then
  echo "SDD verification failed: AGENTS.md missing design-system guidance" >&2
  exit 1
fi

for marker in '历史来源与合并结论' 'd416fb9bc288239b42ed899ca07b1339eb9d6f1b/docs/design-spec.md' '平台/客户端/模型/路由'; do
  if ! rg -q --fixed-strings "$marker" docs/DESIGN_SYSTEM.md; then
    echo "SDD verification failed: design system missing historical merge marker '$marker'" >&2
    exit 1
  fi
done

for file in "$spec_file" "$plan_file"; do
  if ! rg -q --fixed-strings 'docs/DESIGN_SYSTEM.md' "$file"; then
    echo "SDD verification failed: $file missing design-system link" >&2
    exit 1
  fi
done

for field in 'id: QMR-001' 'status: implemented' 'provenance: reconstructed'; do
  if ! rg -q --fixed-strings "$field" "$spec_file"; then
    echo "SDD verification failed: spec metadata missing '$field'" >&2
    exit 1
  fi
done

if ! rg -q --fixed-strings 'spec: QMR-001' "$plan_file"; then
  echo "SDD verification failed: plan is not linked to QMR-001" >&2
  exit 1
fi

for number in 001 002 003 004 005 006 007 008 009 010; do
  requirement="REM-$number"
  for file in "$spec_file" "$trace_file"; do
    if ! rg -q --fixed-strings "$requirement" "$file"; then
      echo "SDD verification failed: $requirement missing from $file" >&2
      exit 1
    fi
  done
done

if rg -n --no-messages 'TBD|TODO: fill|待补充内容' "${required_files[@]}"; then
  echo "SDD verification failed: unresolved template placeholder" >&2
  exit 1
fi

echo "SDD documentation verification: passed"
