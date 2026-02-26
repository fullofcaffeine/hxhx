#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PLAN_PATH="$TMP_DIR/typed_seed_plan.json"
SEED="${SEMANTIC_DIFF_SEED:-1337}"
COUNT="${SEMANTIC_DIFF_COUNT:-24}"
SLICE_ID="${SEMANTIC_DIFF_SLICE_ID:-core_seed_v1}"

echo "== semantic-diff typed generator: build plan seed=${SEED} count=${COUNT} slice=${SLICE_ID}"
node scripts/stdlib/generate-semantic-diff-typed-seed-plan.js \
  --seed "$SEED" \
  --count "$COUNT" \
  --slice "$SLICE_ID" \
  --out "$PLAN_PATH" \
  --no-print-json

echo "== semantic-diff typed generator: replay verification"
node scripts/stdlib/generate-semantic-diff-typed-seed-plan.js \
  --replay-config "$PLAN_PATH" \
  --no-print-json

echo "✓ semantic-diff typed generator deterministic replay OK"
