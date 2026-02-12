#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
WORKLOAD_FILTER="${WORKLOAD_FILTER:-}"
WORKLOAD_PROFILE="${WORKLOAD_PROFILE:-fast}"
WORKLOAD_PROGRESS_INTERVAL_SEC="${WORKLOAD_PROGRESS_INTERVAL_SEC:-20}"
WORKLOAD_TIMEOUT_SEC="${WORKLOAD_TIMEOUT_SEC:-0}"
WORKLOAD_HEAVY_TIMEOUT_SEC="${WORKLOAD_HEAVY_TIMEOUT_SEC:-600}"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping workloads: dune/ocamlc not found on PATH."
  exit 0
fi

case "$WORKLOAD_PROFILE" in
  fast|full) ;;
  *)
    echo "Invalid WORKLOAD_PROFILE=$WORKLOAD_PROFILE (expected fast|full)" >&2
    exit 1
    ;;
esac

is_non_negative_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

for numeric_var in WORKLOAD_PROGRESS_INTERVAL_SEC WORKLOAD_TIMEOUT_SEC WORKLOAD_HEAVY_TIMEOUT_SEC; do
  value="${!numeric_var}"
  if ! is_non_negative_int "$value"; then
    echo "Invalid $numeric_var=$value (expected non-negative integer seconds)" >&2
    exit 1
  fi
done

run_with_progress() {
  local label="$1"
  local timeout_sec="$2"
  shift 2

  local started_at now elapsed last_report_at
  started_at="$(date +%s)"
  last_report_at="$started_at"

  "$@" &
  local cmd_pid="$!"

  while kill -0 "$cmd_pid" 2>/dev/null; do
    now="$(date +%s)"
    elapsed="$(( now - started_at ))"

    if [ "$timeout_sec" -gt 0 ] && [ "$elapsed" -ge "$timeout_sec" ]; then
      echo "   ${label}: timeout after ${elapsed}s (budget=${timeout_sec}s), terminating"
      kill -TERM "$cmd_pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$cmd_pid" 2>/dev/null || true
      wait "$cmd_pid" || true
      return 124
    fi

    if [ "$WORKLOAD_PROGRESS_INTERVAL_SEC" -gt 0 ] && [ $(( now - last_report_at )) -ge "$WORKLOAD_PROGRESS_INTERVAL_SEC" ]; then
      echo "   ${label}: still running (${elapsed}s elapsed)"
      last_report_at="$now"
    fi

    sleep 1
  done

  wait "$cmd_pid"
}

compile_timeout_for_workload() {
  local is_heavy="$1"
  if [ "$WORKLOAD_TIMEOUT_SEC" -gt 0 ]; then
    echo "$WORKLOAD_TIMEOUT_SEC"
    return 0
  fi
  if [ "$is_heavy" -eq 1 ]; then
    echo "$WORKLOAD_HEAVY_TIMEOUT_SEC"
    return 0
  fi
  echo "0"
}

overall_started_at="$(date +%s)"
ran_count=0
heavy_ran_count=0
skipped_filter_count=0
skipped_profile_count=0

for dir in workloads/*/; do
  [ -f "${dir}build.hxml" ] || continue

  name="$(basename "$dir")"
  is_heavy=0
  if [ -f "${dir}HEAVY_WORKLOAD" ]; then
    is_heavy=1
  fi

  if [ -n "$WORKLOAD_FILTER" ] && [[ "$name" != *"$WORKLOAD_FILTER"* ]]; then
    skipped_filter_count=$((skipped_filter_count + 1))
    continue
  fi

  if [ "$WORKLOAD_PROFILE" = "fast" ] && [ "$is_heavy" -eq 1 ] && [ -z "$WORKLOAD_FILTER" ]; then
    echo "== Workload: ${dir} (skipped: heavy workload in fast profile)"
    skipped_profile_count=$((skipped_profile_count + 1))
    continue
  fi

  compile_timeout="$(compile_timeout_for_workload "$is_heavy")"
  workload_started_at="$(date +%s)"

  echo "== Workload: ${dir}"
  if [ "$compile_timeout" -gt 0 ]; then
    echo "   compile timeout budget: ${compile_timeout}s"
  fi

  (
    cd "$dir"
    rm -rf out
    mkdir -p out

    compile_started_at="$(date +%s)"
    echo "   compile: build.hxml"
    run_with_progress "compile" "$compile_timeout" "$HAXE_BIN" build.hxml -D ocaml_build=native
    compile_elapsed="$(( $(date +%s) - compile_started_at ))"

    exe="out/_build/default/out.exe"
    if [ ! -f "$exe" ]; then
      echo "Missing built executable: ${dir}${exe}" >&2
      exit 1
    fi

    run_started_at="$(date +%s)"
    echo "   run: $exe"
    tmp="$(mktemp)"
    HX_TEST_ENV=ok "./$exe" > "$tmp"
    diff -u "expected.stdout" "$tmp"
    rm -f "$tmp"
    run_elapsed="$(( $(date +%s) - run_started_at ))"

    total_elapsed="$(( $(date +%s) - workload_started_at ))"
    echo "   timing: compile=${compile_elapsed}s run=${run_elapsed}s total=${total_elapsed}s"
  )

  ran_count=$((ran_count + 1))
  if [ "$is_heavy" -eq 1 ]; then
    heavy_ran_count=$((heavy_ran_count + 1))
  fi
done

overall_elapsed="$(( $(date +%s) - overall_started_at ))"
echo "== Workload summary: profile=${WORKLOAD_PROFILE} ran=${ran_count} heavy_ran=${heavy_ran_count} skipped_profile=${skipped_profile_count} skipped_filter=${skipped_filter_count} total=${overall_elapsed}s"

if [ "$ran_count" -eq 0 ] && [ -n "$WORKLOAD_FILTER" ]; then
  echo "No workloads matched WORKLOAD_FILTER=${WORKLOAD_FILTER}" >&2
  exit 1
fi
