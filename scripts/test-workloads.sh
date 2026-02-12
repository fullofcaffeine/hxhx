#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
WORKLOAD_FILTER="${WORKLOAD_FILTER:-}"
WORKLOAD_PROGRESS_INTERVAL_SEC="${WORKLOAD_PROGRESS_INTERVAL_SEC:-20}"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping workloads: dune/ocamlc not found on PATH."
  exit 0
fi

run_with_progress() {
  local label="$1"
  shift

  local started_at
  started_at="$(date +%s)"

  "$@" &
  local cmd_pid="$!"

  while kill -0 "$cmd_pid" 2>/dev/null; do
    sleep "$WORKLOAD_PROGRESS_INTERVAL_SEC"
    if kill -0 "$cmd_pid" 2>/dev/null; then
      local elapsed
      elapsed="$(( $(date +%s) - started_at ))"
      echo "   ${label}: still running (${elapsed}s elapsed)"
    fi
  done

  wait "$cmd_pid"
}

for dir in workloads/*/; do
  [ -f "${dir}build.hxml" ] || continue

  name="$(basename "$dir")"
  if [ -n "$WORKLOAD_FILTER" ] && [[ "$name" != *"$WORKLOAD_FILTER"* ]]; then
    continue
  fi

  echo "== Workload: ${dir}"

  (
    cd "$dir"
    rm -rf out
    mkdir -p out

    echo "   compile: build.hxml"
    run_with_progress "compile" "$HAXE_BIN" build.hxml -D ocaml_build=native

    exe="out/_build/default/out.exe"
    if [ ! -f "$exe" ]; then
      echo "Missing built executable: ${dir}${exe}" >&2
      exit 1
    fi

    echo "   run: $exe"
    tmp="$(mktemp)"
    HX_TEST_ENV=ok "./$exe" > "$tmp"
    diff -u "expected.stdout" "$tmp"
    rm -f "$tmp"
  )
done
