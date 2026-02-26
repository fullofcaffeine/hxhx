#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CORPUS_MANIFEST="${SEMANTIC_DIFF_CORPUS_MANIFEST:-test/portable/semantic_diff/corpus_v1.json}"
SEMANTIC_DIFF_SLICE_ID="${SEMANTIC_DIFF_SLICE_ID:-core_seed_v1}"

if [ ! -f "$CORPUS_MANIFEST" ]; then
  echo "Missing semantic-diff corpus manifest: $CORPUS_MANIFEST" >&2
  exit 2
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Missing node on PATH; required to parse semantic-diff corpus manifest." >&2
  exit 2
fi

SEED_FIXTURES="$(
  node -e '
const fs = require("fs");
const manifestPath = process.argv[1];
const sliceId = process.argv[2];
const corpus = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
if (!Array.isArray(corpus.slices)) {
  console.error("Invalid corpus manifest: missing slices array");
  process.exit(2);
}
const slice = corpus.slices.find((value) => value.id === sliceId);
if (!slice) {
  console.error(`Missing semantic-diff slice: ${sliceId}`);
  process.exit(2);
}
if (!Array.isArray(slice.fixtures) || slice.fixtures.length === 0) {
  console.error(`Semantic-diff slice has no fixtures: ${sliceId}`);
  process.exit(2);
}
const normalized = slice.fixtures.map((value) => String(value).trim()).filter((value) => value.length > 0);
if (normalized.length === 0) {
  console.error(`Semantic-diff slice has only empty fixture IDs: ${sliceId}`);
  process.exit(2);
}
process.stdout.write(normalized.join(","));
' "$CORPUS_MANIFEST" "$SEMANTIC_DIFF_SLICE_ID"
)"

echo "PORTABLE_CONFORMANCE_RUNNER_START target=ocaml tier=semantic_diff_seed slice=${SEMANTIC_DIFF_SLICE_ID}"
PORTABLE_NATIVE_SURFACE_STRICT=1 PORTABLE_FIXTURE_ALLOWLIST="$SEED_FIXTURES" bash scripts/test-portable.sh
echo "PORTABLE_CONFORMANCE_RUNNER_PASS target=ocaml tier=semantic_diff_seed slice=${SEMANTIC_DIFF_SLICE_ID}"
