#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

LEFT_REPORT="$TMP_DIR/adapter_left.json"
RIGHT_REPORT="$TMP_DIR/adapter_right.json"
DIVERGENCE_REPORT="$TMP_DIR/divergence_report.json"
SLICE_ID="${SEMANTIC_DIFF_SLICE_ID:-core_seed_v1}"
STRICT_NATIVE_SURFACE="${SEMANTIC_DIFF_STRICT_NATIVE_SURFACE:-true}"

echo "== semantic-diff comparator: build left adapter report"
node scripts/stdlib/run-semantic-diff-adapter-ocaml.js \
  --adapter-id ocaml_left \
  --slice "$SLICE_ID" \
  --strict-native-surface "$STRICT_NATIVE_SURFACE" \
  --out "$LEFT_REPORT" \
  --no-print-json

echo "== semantic-diff comparator: build right adapter report"
node scripts/stdlib/run-semantic-diff-adapter-ocaml.js \
  --adapter-id ocaml_right \
  --slice "$SLICE_ID" \
  --strict-native-surface "$STRICT_NATIVE_SURFACE" \
  --out "$RIGHT_REPORT" \
  --no-print-json

echo "== semantic-diff comparator: compare normalized outputs"
node scripts/stdlib/compare-semantic-diff-adapter-reports.js \
  --left "$LEFT_REPORT" \
  --right "$RIGHT_REPORT" \
  --out "$DIVERGENCE_REPORT" \
  --no-print-json

DIVERGENCE_COUNT="$(
  node -e '
const fs = require("fs");
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (report?.summary?.divergenceCount == null) {
  console.error("missing divergenceCount in report");
  process.exit(2);
}
process.stdout.write(String(report.summary.divergenceCount));
' "$DIVERGENCE_REPORT"
)"

if [ "$DIVERGENCE_COUNT" != "0" ]; then
  echo "Semantic diff comparator detected ${DIVERGENCE_COUNT} divergences." >&2
  echo "Report: $DIVERGENCE_REPORT" >&2
  exit 1
fi

echo "✓ semantic-diff comparator normalized-output smoke OK"
