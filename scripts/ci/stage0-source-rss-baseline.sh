#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extract_peak_script="$ROOT/scripts/ci/extract-stage0-peak-rss.sh"

samples=5
run_limit=30
workflow_name="Stage0 Source Smoke"
job_name="Stage0 source-build smoke"
allow_partial=0
include_failures=0

usage() {
  cat <<EOF
Usage: bash scripts/ci/stage0-source-rss-baseline.sh [options]

Options:
  --samples <n>         Number of successful runs to sample (default: $samples)
  --run-limit <n>       Max workflow runs to scan (default: $run_limit)
  --workflow <name>     Workflow name to scan (default: "$workflow_name")
  --job <name>          Job name inside runs (default: "$job_name")
  --allow-partial       Exit 0 when fewer than --samples runs are found
  --include-failures    Include failed runs/jobs in sample set
  -h, --help            Show this help

Requires:
  - gh CLI authenticated for this repository
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --samples)
      samples="${2:-}"
      shift 2
      ;;
    --run-limit)
      run_limit="${2:-}"
      shift 2
      ;;
    --workflow)
      workflow_name="${2:-}"
      shift 2
      ;;
    --job)
      job_name="${2:-}"
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

case "$samples" in
  ''|*[!0-9]*)
    echo "Invalid --samples value: $samples (expected positive integer)." >&2
    exit 2
    ;;
esac
case "$run_limit" in
  ''|*[!0-9]*)
    echo "Invalid --run-limit value: $run_limit (expected positive integer)." >&2
    exit 2
    ;;
esac
if [ "$samples" -lt 1 ] || [ "$run_limit" -lt 1 ]; then
  echo "--samples and --run-limit must be >= 1." >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Missing gh CLI." >&2
  exit 2
fi
if [ ! -x "$extract_peak_script" ]; then
  echo "Missing executable helper: $extract_peak_script" >&2
  exit 2
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_entries_file="$tmp_dir/run_entries.txt"
if [ "$include_failures" = "1" ]; then
  gh run list \
    --workflow "$workflow_name" \
    --limit "$run_limit" \
    --json databaseId,status,conclusion \
    --jq '.[] | select(.status=="completed" and (.conclusion=="success" or .conclusion=="failure")) | "\(.databaseId):\(.conclusion)"' >"$run_entries_file"
else
  gh run list \
    --workflow "$workflow_name" \
    --limit "$run_limit" \
    --json databaseId,status,conclusion \
    --jq '.[] | select(.status=="completed" and .conclusion=="success") | "\(.databaseId):\(.conclusion)"' >"$run_entries_file"
fi

run_entries=()
while IFS= read -r run_entry; do
  if [ -z "$run_entry" ]; then
    continue
  fi
  run_entries+=("$run_entry")
done <"$run_entries_file"

if [ "${#run_entries[@]}" -eq 0 ]; then
  if [ "$include_failures" = "1" ]; then
    echo "No successful/failed completed runs found for workflow: $workflow_name"
  else
    echo "No successful runs found for workflow: $workflow_name"
  fi
  if [ "$allow_partial" = "1" ]; then
    exit 0
  fi
  exit 3
fi

declare -a sampled_runs=()
declare -a sampled_conclusions=()
declare -a sampled_peaks=()

for run_entry in "${run_entries[@]}"; do
  if [ "${#sampled_runs[@]}" -ge "$samples" ]; then
    break
  fi

  run_id="${run_entry%%:*}"
  run_conclusion="${run_entry#*:}"

  if [ "$include_failures" = "1" ]; then
    job_id="$(
      gh run view "$run_id" --json jobs \
        --jq ".jobs[] | select(.name==\"$job_name\" and (.conclusion==\"success\" or .conclusion==\"failure\")) | .databaseId" \
        | head -n 1
    )"
  else
    job_id="$(
      gh run view "$run_id" --json jobs \
        --jq ".jobs[] | select(.name==\"$job_name\" and .conclusion==\"success\") | .databaseId" \
        | head -n 1
    )"
  fi

  if [ -z "$job_id" ]; then
    continue
  fi

  log_file="$tmp_dir/${run_id}.log"
  if ! gh run view "$run_id" --job "$job_id" --log >"$log_file"; then
    continue
  fi

  peak="$("$extract_peak_script" "$log_file")"
  if [ "$peak" = "0" ]; then
    continue
  fi

  sampled_runs+=("$run_id")
  sampled_conclusions+=("$run_conclusion")
  sampled_peaks+=("$peak")
done

count="${#sampled_runs[@]}"
if [ "$count" -eq 0 ]; then
  if [ "$include_failures" = "1" ]; then
    echo "No successful/failed '$job_name' logs with Stage0 RSS samples were found."
  else
    echo "No successful '$job_name' logs with Stage0 RSS samples were found."
  fi
  if [ "$allow_partial" = "1" ]; then
    exit 0
  fi
  exit 4
fi

echo "Stage0 RSS samples (workflow=\"$workflow_name\" job=\"$job_name\"):"
for i in "${!sampled_runs[@]}"; do
  echo "- run_id=${sampled_runs[$i]} conclusion=${sampled_conclusions[$i]} peak_tree_rss_mb=${sampled_peaks[$i]}"
done

min_peak="$(printf '%s\n' "${sampled_peaks[@]}" | sort -n | head -n 1)"
max_peak="$(printf '%s\n' "${sampled_peaks[@]}" | sort -n | tail -n 1)"
avg_peak="$(
  printf '%s\n' "${sampled_peaks[@]}" \
    | awk '{sum += $1; count += 1} END {if (count == 0) {print 0} else {printf "%.1f", sum / count}}'
)"
median_peak="$(
  printf '%s\n' "${sampled_peaks[@]}" \
    | sort -n \
    | awk '{a[NR] = $1} END {if (NR == 0) {print 0} else if (NR % 2 == 1) {print a[(NR + 1) / 2]} else {printf "%.1f", (a[NR / 2] + a[NR / 2 + 1]) / 2}}'
)"

echo "summary samples=${count} requested=${samples} min=${min_peak}MB median=${median_peak}MB avg=${avg_peak}MB max=${max_peak}MB"

if [ "$count" -lt "$samples" ] && [ "$allow_partial" != "1" ]; then
  echo "Only ${count} usable samples collected (requested ${samples})." >&2
  exit 5
fi
