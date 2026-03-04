#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASELINE_SCRIPT="$ROOT/scripts/ci/stage0-progress-hotspot-baseline.js"

workflow_name="Smoke / Stage0 Source Build"
artifact_prefix="stage0-source-smoke-profile"
samples=5
run_limit=30
min_presence=2
top=10
sort_key="median"
allow_partial=0
include_failures=0
current_summary=""
json_out=""
text_out=""

usage() {
  cat <<EOF_USAGE
Usage: bash scripts/ci/stage0-progress-hotspot-gh-baseline.sh [options]

Download recent profile artifacts from GitHub Actions runs and print hotspot baseline regression.

Options:
  --workflow <name>         Workflow name to scan (default: "$workflow_name")
  --artifact-prefix <name>  Artifact prefix; script expects <prefix>-<run_id>
                            (default: "$artifact_prefix")
  --samples <n>             Total summaries to compare including current (default: $samples)
  --run-limit <n>           Max workflow runs to scan (default: $run_limit)
  --min-presence <n>        Require hotspot presence in >=n runs (default: $min_presence)
  --top <n>                 Number of hotspot rows (default: $top)
  --sort <key>              Sort key (median|avg|total|max|presence, default: $sort_key)
  --allow-partial           Exit 0 if fewer than --samples summaries are available
  --include-failures        Include failed runs when searching artifacts
  --current-summary <path>  Local current-run progress_summary.json (appended as latest)
  --json-out <path>         Compare JSON output path
  --text-out <path>         Text output path
  -h, --help                Show this help

Requires:
  - gh CLI authenticated for this repository
  - node available on PATH
EOF_USAGE
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
    *)
      [ "$1" -ge 1 ]
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workflow)
      workflow_name="${2:-}"
      shift 2
      ;;
    --artifact-prefix)
      artifact_prefix="${2:-}"
      shift 2
      ;;
    --samples)
      samples="${2:-}"
      shift 2
      ;;
    --run-limit)
      run_limit="${2:-}"
      shift 2
      ;;
    --min-presence)
      min_presence="${2:-}"
      shift 2
      ;;
    --top)
      top="${2:-}"
      shift 2
      ;;
    --sort)
      sort_key="${2:-}"
      shift 2
      ;;
    --allow-partial)
      allow_partial=1
      shift
      ;;
    --include-failures)
      include_failures=1
      shift
      ;;
    --current-summary)
      current_summary="${2:-}"
      shift 2
      ;;
    --json-out)
      json_out="${2:-}"
      shift 2
      ;;
    --text-out)
      text_out="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! is_positive_int "$samples"; then
  echo "Invalid --samples value: $samples (expected positive integer)." >&2
  exit 2
fi
if ! is_positive_int "$run_limit"; then
  echo "Invalid --run-limit value: $run_limit (expected positive integer)." >&2
  exit 2
fi
if ! is_positive_int "$min_presence"; then
  echo "Invalid --min-presence value: $min_presence (expected positive integer)." >&2
  exit 2
fi
if ! is_positive_int "$top"; then
  echo "Invalid --top value: $top (expected positive integer)." >&2
  exit 2
fi
case "$sort_key" in
  median|avg|total|max|presence)
    ;;
  *)
    echo "Invalid --sort value: $sort_key (expected median|avg|total|max|presence)." >&2
    exit 2
    ;;
esac

if [ "$samples" -lt 2 ]; then
  echo "--samples must be >= 2 for baseline/latest comparison." >&2
  exit 2
fi
if [ "$min_presence" -gt "$samples" ]; then
  echo "--min-presence cannot exceed --samples." >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Missing gh CLI." >&2
  exit 2
fi
if ! command -v node >/dev/null 2>&1; then
  echo "Missing node runtime." >&2
  exit 2
fi
if [ ! -f "$BASELINE_SCRIPT" ]; then
  echo "Missing helper script: $BASELINE_SCRIPT" >&2
  exit 2
fi
if [ -n "$current_summary" ] && [ ! -f "$current_summary" ]; then
  echo "Missing --current-summary file: $current_summary" >&2
  exit 2
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_entries_file="$tmp_dir/run_entries.txt"
if [ "$include_failures" = "1" ]; then
  run_list_jq='.[] | select(.status=="completed" and (.conclusion=="success" or .conclusion=="failure")) | "\(.databaseId):\(.conclusion)"'
else
  run_list_jq='.[] | select(.status=="completed" and .conclusion=="success") | "\(.databaseId):\(.conclusion)"'
fi

if ! gh run list --workflow "$workflow_name" --limit "$run_limit" --json databaseId,status,conclusion --jq "$run_list_jq" >"$run_entries_file"; then
  if [ "$allow_partial" != "1" ]; then
    echo "Failed to list runs for workflow: $workflow_name" >&2
    exit 3
  fi
  : >"$run_entries_file"
fi

history_target="$samples"
if [ -n "$current_summary" ]; then
  history_target="$((samples - 1))"
fi
if [ "$history_target" -lt 0 ]; then
  history_target=0
fi

declare -a hist_paths=()
declare -a hist_meta=()
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  if [ "${#hist_paths[@]}" -ge "$history_target" ]; then
    break
  fi

  run_id="${entry%%:*}"
  conclusion="${entry#*:}"
  artifact_name="${artifact_prefix}-${run_id}"
  run_dir="$tmp_dir/run-${run_id}"
  mkdir -p "$run_dir"

  if ! gh run download "$run_id" -n "$artifact_name" --dir "$run_dir" >/dev/null 2>&1; then
    continue
  fi

  summary_path="$(find "$run_dir" -type f -name progress_summary.json | head -n 1 || true)"
  if [ -z "$summary_path" ]; then
    continue
  fi

  hist_paths+=("$summary_path")
  hist_meta+=("run_id=$run_id conclusion=$conclusion artifact=$artifact_name summary=$summary_path")
done <"$run_entries_file"

declare -a selected_paths=()
declare -a selected_meta=()
for (( i=${#hist_paths[@]}-1; i>=0; i-- )); do
  selected_paths+=("${hist_paths[$i]}")
  selected_meta+=("${hist_meta[$i]}")
done

if [ -n "$current_summary" ]; then
  selected_paths+=("$current_summary")
  selected_meta+=("run_id=current conclusion=local artifact=none summary=$current_summary")
fi

selected_count="${#selected_paths[@]}"
if [ "$selected_count" -lt 2 ]; then
  msg="Need at least 2 summaries for baseline comparison (found $selected_count)."
  if [ "$allow_partial" = "1" ]; then
    echo "$msg"
    exit 0
  fi
  echo "$msg" >&2
  exit 4
fi
if [ "$selected_count" -lt "$samples" ] && [ "$allow_partial" != "1" ]; then
  echo "Only $selected_count summaries found (requested $samples)." >&2
  exit 5
fi

echo "stage0_hotspot_summary_sources:"
for meta in "${selected_meta[@]}"; do
  echo "- $meta"
done

cmd=(node "$BASELINE_SCRIPT" --samples "$samples" --top "$top" --min-presence "$min_presence" --sort "$sort_key")
if [ "$allow_partial" = "1" ]; then
  cmd+=(--allow-partial)
fi
if [ -n "$json_out" ]; then
  cmd+=(--json-out "$json_out")
fi
if [ -n "$text_out" ]; then
  cmd+=(--text-out "$text_out")
fi
for summary_path in "${selected_paths[@]}"; do
  cmd+=(--summary "$summary_path")
done

"${cmd[@]}"
