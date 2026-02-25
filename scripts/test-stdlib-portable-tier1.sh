#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== stdlib portable tier1: tier1 allowlist check"
node scripts/ci/portable-stdlib-tier-allowlist-check.js --tier tier1

echo "== stdlib portable tier1: portable fixture suite"
PORTABLE_NATIVE_SURFACE_STRICT=1 bash scripts/test-portable.sh

echo "✓ stdlib portable tier1 OK"
