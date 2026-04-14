#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PILOT_SCRIPT="$ROOT/scripts/hxhx/run-reflaxe-elixir-todo-promotion-pilot.sh"

if [ ! -x "$PILOT_SCRIPT" ]; then
  echo "rpmx hxhx plugin proof: missing pilot script: $PILOT_SCRIPT" >&2
  exit 1
fi

run_id="$(date +%Y%m%d-%H%M%S)"
artifact_dir="${RPMX_HXHX_PLUGIN_ARTIFACT_DIR:-$ROOT/.artifacts/rpmx/hxhx-plugin/$run_id}"
mkdir -p "$artifact_dir"

set +e
pilot_output="$(
  HXHX_PILOT_ARTIFACT_DIR="$artifact_dir" \
    "$PILOT_SCRIPT" 2>&1
)"
pilot_status="$?"
set -e

printf '%s\n' "$pilot_output"
printf '%s\n' "$pilot_output" >"$artifact_dir/rpmx-hxhx-plugin.stdout.log"

if [ "$pilot_status" -ne 0 ]; then
  echo "rpmx hxhx plugin proof: pilot failed with exit $pilot_status" >&2
  exit "$pilot_status"
fi

printf '%s\n' "$pilot_output" | grep -q '^REFLAXE_ELIXIR_PROMOTION_NATIVE:PASS$'

summary="$artifact_dir/rpmx-hxhx-plugin.summary.json"
node <<'NODE' "$artifact_dir" "$summary"
const fs = require('fs')
const artifactDir = process.argv[2]
const summaryPath = process.argv[3]
const pilotSummaryPath = `${artifactDir}/reflaxe-elixir-promotion-native.summary.json`
const pilotSummary = fs.existsSync(pilotSummaryPath)
  ? JSON.parse(fs.readFileSync(pilotSummaryPath, 'utf8'))
  : null

fs.writeFileSync(summaryPath, JSON.stringify({
  workload: 'reflaxe-elixir-todo-promotion-pilot',
  proof: {
    host: 'hxhx',
    mode: 'native-plugin-host-adapter',
    pilotSummary: pilotSummaryPath,
    sourceCommit: pilotSummary ? pilotSummary.sourceCommit : null,
    hxhxBin: pilotSummary ? pilotSummary.hxhxBin : null,
  },
  result: 'RPMX_HXHX_PLUGIN:PASS',
}, null, 2) + '\n')
NODE

echo "rpmx_hxhx_plugin_artifact_dir=$artifact_dir"
echo "rpmx_hxhx_plugin_summary=$summary"
echo "RPMX_HXHX_PLUGIN:PASS"
