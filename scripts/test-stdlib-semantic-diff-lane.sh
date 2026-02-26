#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROFILE="${SEMANTIC_DIFF_PROFILE:-pr}"
SEED="${SEMANTIC_DIFF_SEED:-1337}"
SLICE_ID="${SEMANTIC_DIFF_SLICE_ID:-core_seed_v1}"
TIMEOUT_MS="${SEMANTIC_DIFF_TIMEOUT_MS:-10000}"
if [ "$PROFILE" = "pr" ]; then
  MAX_PROGRAMS="${SEMANTIC_DIFF_MAX_PROGRAMS:-50}"
  COMPARATOR_REPEATS="${SEMANTIC_DIFF_COMPARATOR_REPEATS:-1}"
else
  MAX_PROGRAMS="${SEMANTIC_DIFF_MAX_PROGRAMS:-1000}"
  COMPARATOR_REPEATS="${SEMANTIC_DIFF_COMPARATOR_REPEATS:-2}"
fi
ARTIFACT_DIR="${SEMANTIC_DIFF_ARTIFACT_DIR:-.artifacts/semantic-diff/$PROFILE}"

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

echo "semantic_diff_lane_profile=${PROFILE}"
echo "semantic_diff_lane_seed=${SEED}"
echo "semantic_diff_lane_slice=${SLICE_ID}"
echo "semantic_diff_lane_max_programs=${MAX_PROGRAMS}"
echo "semantic_diff_lane_timeout_ms=${TIMEOUT_MS}"
echo "semantic_diff_lane_comparator_repeats=${COMPARATOR_REPEATS}"

node scripts/stdlib/generate-semantic-diff-typed-seed-plan.js \
  --seed "$SEED" \
  --count "$MAX_PROGRAMS" \
  --slice "$SLICE_ID" \
  --out "$ARTIFACT_DIR/typed_seed_plan.json" \
  --no-print-json

for run_index in $(seq 1 "$COMPARATOR_REPEATS"); do
  RUN_DIR="$ARTIFACT_DIR/run_${run_index}"
  mkdir -p "$RUN_DIR"
  node scripts/stdlib/run-semantic-diff-adapter-ocaml.js \
    --adapter-id "ocaml_left" \
    --slice "$SLICE_ID" \
    --strict-native-surface true \
    --out "$RUN_DIR/adapter_left.json" \
    --no-print-json
  node scripts/stdlib/run-semantic-diff-adapter-ocaml.js \
    --adapter-id "ocaml_right" \
    --slice "$SLICE_ID" \
    --strict-native-surface true \
    --out "$RUN_DIR/adapter_right.json" \
    --no-print-json
  node scripts/stdlib/compare-semantic-diff-adapter-reports.js \
    --left "$RUN_DIR/adapter_left.json" \
    --right "$RUN_DIR/adapter_right.json" \
    --out "$RUN_DIR/divergence_report.json" \
    --no-print-json
done

CLASSIFICATION_PATH="$ARTIFACT_DIR/classification.json"
PRIMARY_REPORT="$ARTIFACT_DIR/run_1/divergence_report.json"

DIVERGENCE_COUNT="$(
  node -e '
const fs = require("fs");
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (report?.summary?.divergenceCount == null) {
  console.error("missing divergenceCount");
  process.exit(2);
}
process.stdout.write(String(report.summary.divergenceCount));
' "$PRIMARY_REPORT"
)"

STABILITY_STATUS="stable"
STABILITY_REASON="single_run"
if [ "$COMPARATOR_REPEATS" -gt 1 ]; then
  HASHES="$(
    node -e '
const fs = require("fs");
const crypto = require("crypto");
const baseDir = process.argv[1];
const repeats = Number.parseInt(process.argv[2], 10);
const hashes = [];
for (let i = 1; i <= repeats; i += 1) {
  const filePath = `${baseDir}/run_${i}/divergence_report.json`;
  const report = JSON.parse(fs.readFileSync(filePath, "utf8"));
  const stableProjection = {
    contractId: report.contractId,
    contractVersion: report.contractVersion,
    summary: report.summary,
    divergences: report.divergences,
  };
  hashes.push(crypto.createHash("sha256").update(JSON.stringify(stableProjection)).digest("hex"));
}
process.stdout.write(JSON.stringify(hashes));
' "$ARTIFACT_DIR" "$COMPARATOR_REPEATS"
  )"
  HASH_COUNT="$(
    node -e '
const hashes = JSON.parse(process.argv[1]);
const unique = new Set(hashes);
process.stdout.write(String(unique.size));
' "$HASHES"
  )"
  if [ "$HASH_COUNT" != "1" ]; then
    STABILITY_STATUS="unstable"
    STABILITY_REASON="report_hash_mismatch"
  else
    STABILITY_STATUS="stable"
    STABILITY_REASON="hash_consistent"
  fi
fi

node -e '
const fs = require("fs");
const payload = {
  schemaVersion: 1,
  contractId: "reflaxe.family.std.semantic_diff_lane_classification",
  contractVersion: "1.0.0",
  profile: process.argv[1],
  status: process.argv[2],
  reason: process.argv[3],
  caps: {
    seed: Number.parseInt(process.argv[4], 10),
    maxPrograms: Number.parseInt(process.argv[5], 10),
    timeoutMs: Number.parseInt(process.argv[6], 10),
    comparatorRepeats: Number.parseInt(process.argv[7], 10),
  },
  summary: {
    divergenceCount: Number.parseInt(process.argv[8], 10),
  },
};
fs.writeFileSync(process.argv[9], `${JSON.stringify(payload, null, 2)}\n`, "utf8");
' "$PROFILE" "$STABILITY_STATUS" "$STABILITY_REASON" "$SEED" "$MAX_PROGRAMS" "$TIMEOUT_MS" "$COMPARATOR_REPEATS" "$DIVERGENCE_COUNT" "$CLASSIFICATION_PATH"

node scripts/stdlib/minimize-semantic-diff-divergences.js \
  --divergence-report "$PRIMARY_REPORT" \
  --out-dir "$ARTIFACT_DIR/minimized" \
  --no-print-json

echo "semantic_diff_lane_status=${STABILITY_STATUS}"
echo "semantic_diff_lane_reason=${STABILITY_REASON}"
echo "semantic_diff_lane_divergence_count=${DIVERGENCE_COUNT}"
echo "semantic_diff_lane_artifact_dir=${ARTIFACT_DIR}"

if [ "$STABILITY_STATUS" = "unstable" ]; then
  echo "Semantic-diff lane classified as unstable; refusing auto-promotion." >&2
  exit 1
fi

echo "✓ semantic-diff lane ${PROFILE} OK"
