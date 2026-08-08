#!/usr/bin/env bash
set -euo pipefail

# Prove that one real source file keeps every numeric value through generated
# JavaScript and runtime execution. The upstream compiler supplies an
# independent behavior oracle. The candidate compiler can come from the
# committed bootstrap, current Haxe sources, or an explicit binary.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:-snapshot}"
FIXTURE="$ROOT/test/fixtures/hxhx_complete_numeric_literals"
EXPECTED="$FIXTURE/expected.stdout"
VERIFY_JS="$ROOT/scripts/hxhx/verify-complete-numeric-literal-js.js"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hxhx-complete-numeric-literals.XXXXXX")"

cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

normalize_stdout() {
  sed -n 's/^.*HXHX_NUMERIC_LITERALS:/HXHX_NUMERIC_LITERALS:/p' "$1"
}

compile_and_run() {
  local compiler="$1"
  local output="$2"
  local compile_log="$3"
  local stdout_file="$4"

  if ! "$compiler" -cp "$FIXTURE" -main Main -js "$output" >"$compile_log" 2>&1; then
    cat "$compile_log" >&2
    return 1
  fi
  node "$VERIFY_JS" "$output"
  node "$output" >"$stdout_file"
}

UPSTREAM_JS="$WORK/upstream.js"
UPSTREAM_LOG="$WORK/upstream.compile.log"
UPSTREAM_RAW="$WORK/upstream.raw.stdout"
UPSTREAM_STDOUT="$WORK/upstream.stdout"
compile_and_run "${HAXE_BIN:-haxe}" "$UPSTREAM_JS" "$UPSTREAM_LOG" "$UPSTREAM_RAW"
normalize_stdout "$UPSTREAM_RAW" >"$UPSTREAM_STDOUT"
cmp -s "$EXPECTED" "$UPSTREAM_STDOUT" || {
  echo "Upstream Haxe does not match the reviewed numeric-literal expectation." >&2
  diff -u "$EXPECTED" "$UPSTREAM_STDOUT" >&2 || true
  exit 1
}

case "$MODE" in
  snapshot)
    CANDIDATE_BIN="$(
      HXHX_FORBID_STAGE0=1 \
      HXHX_BOOTSTRAP_BUILD_DIR="$WORK/bootstrap-build" \
      HXHX_BOOTSTRAP_BUILD_PRUNE=0 \
      bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1
    )"
    ;;
  current-source)
    CANDIDATE_BIN="$(
      HXHX_STAGE0_OUTPUT_DIR="$WORK/current-source-out" \
      HXHX_CURRENT_SOURCE_META="$WORK/current-source.env" \
      HXHX_CURRENT_SOURCE_INPUT_REPORT="$WORK/current-source-inputs.json" \
      HXHX_BOOTSTRAP_BUILD_PRUNE=0 \
      bash "$ROOT/scripts/hxhx/build-current-source-hxhx.sh" | tail -n 1
    )"
    ;;
  binary)
    CANDIDATE_BIN="${2:-}"
    if [ -z "$CANDIDATE_BIN" ]; then
      echo "Usage: test-complete-numeric-literals.sh binary <hxhx-binary>" >&2
      exit 2
    fi
    ;;
  *)
    echo "Unknown numeric-literal test mode: $MODE" >&2
    exit 2
    ;;
esac

if [ ! -f "$CANDIDATE_BIN" ]; then
  echo "The candidate hxhx binary does not exist: $CANDIDATE_BIN" >&2
  exit 1
fi

CANDIDATE_JS="$WORK/candidate.js"
CANDIDATE_FIRST="$WORK/candidate.first.js"
CANDIDATE_LOG="$WORK/candidate.compile.log"
CANDIDATE_RAW="$WORK/candidate.raw.stdout"
CANDIDATE_STDOUT="$WORK/candidate.stdout"

compile_and_run "$CANDIDATE_BIN" "$CANDIDATE_JS" "$CANDIDATE_LOG" "$CANDIDATE_RAW"
cp "$CANDIDATE_JS" "$CANDIDATE_FIRST"
normalize_stdout "$CANDIDATE_RAW" >"$CANDIDATE_STDOUT"
cmp -s "$EXPECTED" "$CANDIDATE_STDOUT" || {
  echo "The $MODE hxhx compiler changed numeric-literal behavior." >&2
  diff -u "$EXPECTED" "$CANDIDATE_STDOUT" >&2 || true
  exit 1
}

compile_and_run "$CANDIDATE_BIN" "$CANDIDATE_JS" "$CANDIDATE_LOG" "$CANDIDATE_RAW"
cmp -s "$CANDIDATE_FIRST" "$CANDIDATE_JS" || {
  echo "The $MODE hxhx compiler produced different JavaScript for the same input." >&2
  diff -u "$CANDIDATE_FIRST" "$CANDIDATE_JS" >&2 || true
  exit 1
}

echo "HXHX_COMPLETE_NUMERIC_LITERALS:PASS mode=$MODE"
