#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stage0-heartbeat-summary.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

TRACE="$TMP_DIR/stage0_heartbeat_trace.jsonl"
JSON_OUT="$TMP_DIR/heartbeat_summary.json"
TEXT_OUT="$TMP_DIR/heartbeat_summary.txt"

cat >"$TRACE" <<'JSONL'
{"elapsed_sec":1,"pid":101,"focus_pid":101,"child_pid":201,"rss_mb":120,"tree_rss_mb":180,"cpu_pct":12.5,"state":"S","log_bytes":10}
{"elapsed_sec":2,"pid":101,"focus_pid":101,"child_pid":202,"rss_mb":250,"tree_rss_mb":340,"cpu_pct":70.1,"state":"R","log_bytes":30}
not-json
{"elapsed_sec":4,"pid":101,"focus_pid":101,"child_pid":203,"rss_mb":210,"tree_rss_mb":420,"cpu_pct":66.6,"state":"R","log_bytes":55}
JSONL

node "$ROOT/scripts/hxhx/summarize-stage0-heartbeat-trace.js" \
  --input "$TRACE" \
  --top 2 \
  --json-out "$JSON_OUT" \
  --text-out "$TEXT_OUT" >/dev/null

node - "$JSON_OUT" "$TEXT_OUT" <<'NODE'
const fs = require('fs');
const summary = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const text = fs.readFileSync(process.argv[3], 'utf8');

function assert(cond, msg) {
  if (!cond) {
    console.error(msg);
    process.exit(1);
  }
}

assert(summary.schema === 'stage0-heartbeat-summary.v1', 'schema mismatch');
assert(summary.sample_count === 3, `sample_count mismatch: ${summary.sample_count}`);
assert(summary.invalid_line_count === 1, `invalid_line_count mismatch: ${summary.invalid_line_count}`);
assert(summary.elapsed_seconds.first === 1, 'elapsed first mismatch');
assert(summary.elapsed_seconds.last === 4, 'elapsed last mismatch');
assert(summary.elapsed_seconds.duration === 3, 'elapsed duration mismatch');
assert(summary.log_bytes.delta === 45, 'log delta mismatch');
assert(summary.peak_rss_mb.rss_mb === 250, 'peak focus RSS mismatch');
assert(summary.peak_tree_rss_mb.tree_rss_mb === 420, 'peak tree RSS mismatch');
assert(summary.top_tree_rss_samples.length === 2, 'top sample count mismatch');
assert(summary.top_tree_rss_samples[0].child_pid === 203, 'top sample ordering mismatch');
assert(text.includes('heartbeat_trace_summary:'), 'missing text summary header');
assert(text.includes('peak_tree_rss_mb=420'), 'missing peak tree RSS text');
NODE

MISSING_JSON="$TMP_DIR/missing.json"
node "$ROOT/scripts/hxhx/summarize-stage0-heartbeat-trace.js" \
  --input "$TMP_DIR/missing.jsonl" \
  --json-out "$MISSING_JSON" >/dev/null

node - "$MISSING_JSON" <<'NODE'
const fs = require('fs');
const summary = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!summary.missing_input || summary.sample_count !== 0) {
  console.error('missing-input summary mismatch');
  process.exit(1);
}
NODE
