#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
suite_started_at="$(date +%s)"

echo "== stdlib portable tier1: tier1 allowlist check"
phase_started_at="$(date +%s)"
node scripts/ci/portable-stdlib-tier-allowlist-check.js --tier tier1
echo "[stdlib-portable-tier1] phase=allowlist elapsed_seconds=$(($(date +%s) - phase_started_at))"

echo "== stdlib portable tier1: portable fixture suite"
phase_started_at="$(date +%s)"
PORTABLE_NATIVE_SURFACE_STRICT=1 bash scripts/test-portable.sh
echo "[stdlib-portable-tier1] phase=portable-fixtures elapsed_seconds=$(($(date +%s) - phase_started_at))"

echo "[stdlib-portable-tier1] phase=total elapsed_seconds=$(($(date +%s) - suite_started_at))"
echo "✓ stdlib portable tier1 OK"
