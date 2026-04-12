#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_ROOT="${HXHX_STAGE0_FREE_REFRESH_OUT:-$ROOT/.tmp/stage0-free-bootstrap-refresh-probe}"
HAXE_SENTINEL="${HXHX_STAGE0_FREE_REFRESH_HAXE_SENTINEL:-/definitely-not-used}"
SCOPE="${HXHX_STAGE0_FREE_REFRESH_SCOPE:-demo}"
DUNE_JOBS_FOR_BUILD="${HXHX_DUNE_JOBS:-2}"

if [[ "$OUT_ROOT" != /* ]]; then
  OUT_ROOT="$ROOT/$OUT_ROOT"
fi

case "$OUT_ROOT" in
  ""|"/"|"$ROOT"|"$ROOT/")
    echo "Unsafe HXHX_STAGE0_FREE_REFRESH_OUT: $OUT_ROOT" >&2
    exit 2
    ;;
esac

BUILD_DIR="$OUT_ROOT/hxhx-bootstrap-build"
STAGE3_OUT="$OUT_ROOT/stage3_out"
SUMMARY="$OUT_ROOT/summary.txt"
BUILD_LOG="$OUT_ROOT/build-hxhx.log"
STAGE3_LOG="$OUT_ROOT/stage3-emit.log"

KEEP_BOOTSTRAP_BUILD="${HXHX_STAGE0_FREE_REFRESH_KEEP_BUILD:-0}"
KEEP_DUNE_BUILD="${HXHX_STAGE0_FREE_REFRESH_KEEP_DUNE_BUILD:-0}"
STAGE3_TIMEOUT_SEC="${HXHX_STAGE0_FREE_REFRESH_STAGE3_TIMEOUT_SEC:-}"
TARGET_LABEL=""
SOURCE_INPUTS=""
EXPECTED_MARKER=""
REQUIRE_GENERATED_ML=0
REQUIRE_ARTIFACT=0
STAGE3_ARGS=()

cleanup_probe_artifacts() {
  local status=$?
  if [ "$KEEP_BOOTSTRAP_BUILD" != "1" ]; then
    rm -rf "$BUILD_DIR"
  fi
  if [ "$KEEP_DUNE_BUILD" != "1" ]; then
    rm -rf "$STAGE3_OUT/_build" "$STAGE3_OUT"/*.install
    find "$STAGE3_OUT" -type f \( \
      -name '*.cmi' -o \
      -name '*.cmx' -o \
      -name '*.o' -o \
      -name '*.exe' \
    \) -delete 2>/dev/null || true
  fi
  exit "$status"
}

trap cleanup_probe_artifacts EXIT

need_cmd() {
  local cmd="$1"
  local label="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Skipping stage0-free bootstrap refresh probe: missing $label ('$cmd')." >&2
    exit 0
  fi
}

need_cmd dune "dune"
need_cmd ocamlc "ocaml compiler"
need_cmd git "git"

append_stage3_timeout_diagnostics() {
  {
    printf 'generated_ml_count='
    find "$STAGE3_OUT" -type f -name '*.ml' 2>/dev/null | wc -l | tr -d '[:space:]'
    printf '\n'
    echo "recent_stage3_files:"
    ls -lt "$STAGE3_OUT" 2>/dev/null | sed -n '1,20p' || true
  } >>"$STAGE3_LOG"
}

case "$SCOPE" in
  demo)
    TARGET_LABEL="demo-full-emit"
    SOURCE_INPUTS="$ROOT/workloads/hih-compiler/fixtures/src:demo.A"
    EXPECTED_MARKER="stage3=ok"
    REQUIRE_GENERATED_ML=1
    REQUIRE_ARTIFACT=1
    STAGE3_TIMEOUT_SEC="${STAGE3_TIMEOUT_SEC:-120}"
    STAGE3_ARGS=(
      --hxhx-stage3
      --hxhx-emit-full-bodies
      --hxhx-no-run
      -cp "$ROOT/workloads/hih-compiler/fixtures/src"
      -main demo.A
    )
    ;;
  hxhx-type-only|hxhx-full-emit)
    TARGET_LABEL="hxhx-source-type-only"
    EXPECTED_MARKER="stage3=type_only_ok"
    REQUIRE_GENERATED_ML=0
    REQUIRE_ARTIFACT=0
    STAGE3_TIMEOUT_SEC="${STAGE3_TIMEOUT_SEC:-900}"
    STAGE3_ARGS=(
      --hxhx-stage3
      --hxhx-type-only
    )
    if [ "$SCOPE" = "hxhx-full-emit" ]; then
      TARGET_LABEL="hxhx-source-full-emit"
      EXPECTED_MARKER="stage3=ok"
      REQUIRE_GENERATED_ML=1
      REQUIRE_ARTIFACT=1
      STAGE3_TIMEOUT_SEC="${HXHX_STAGE0_FREE_REFRESH_STAGE3_TIMEOUT_SEC:-1800}"
      STAGE3_ARGS=(
        --hxhx-stage3
        --hxhx-emit-full-bodies
        --hxhx-no-run
      )
    fi
    SOURCE_INPUTS="$ROOT/packages/hxhx/src,$ROOT/packages/hxhx-core/src:hxhx.Main"
    STAGE3_ARGS+=(
      -cp "$ROOT/packages/hxhx/src"
      -cp "$ROOT/packages/hxhx-core/src"
      -main hxhx.Main
      -D hih_native_parser
      -D reflaxe_ocaml
      -D no_traces
      -D no-traces
    )
    ;;
  *)
    echo "Unknown HXHX_STAGE0_FREE_REFRESH_SCOPE=$SCOPE (expected demo, hxhx-type-only, or hxhx-full-emit)." >&2
    exit 2
    ;;
esac

case "$STAGE3_TIMEOUT_SEC" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_STAGE0_FREE_REFRESH_STAGE3_TIMEOUT_SEC: $STAGE3_TIMEOUT_SEC (expected non-negative integer)." >&2
    exit 2
    ;;
esac

rm -rf "$OUT_ROOT"
mkdir -p "$OUT_ROOT" "$STAGE3_OUT"

echo "== Stage0-free bootstrap refresh probe"
echo "== Decision: native/self-refresh path; payload slicing remains rejected for release-equivalence risk"
echo "== Scope: $SCOPE ($TARGET_LABEL)"
echo "== Building hxhx from committed snapshots with stage0 delegation forbidden"

set +e
HXHX_FORBID_STAGE0=1 \
  HAXE_BIN="$HAXE_SENTINEL" \
  HXHX_BOOTSTRAP_BUILD_DIR="$BUILD_DIR" \
  HXHX_DUNE_JOBS="$DUNE_JOBS_FOR_BUILD" \
  bash "$ROOT/scripts/hxhx/build-hxhx.sh" >"$BUILD_LOG" 2>&1
build_code=$?
set -e

if [ "$build_code" -ne 0 ]; then
  echo "FAILED: stage0-forbidden hxhx build failed; log: $BUILD_LOG" >&2
  sed -n '1,80p' "$BUILD_LOG" >&2 || true
  exit "$build_code"
fi

HXHX_BIN="$(tail -n 1 "$BUILD_LOG" | tr -d '\r')"
if [ -z "$HXHX_BIN" ] || [ ! -f "$HXHX_BIN" ]; then
  echo "FAILED: missing hxhx binary from build log: $BUILD_LOG" >&2
  tail -n 80 "$BUILD_LOG" >&2 || true
  exit 1
fi

echo "== Running Stage3 scope probe"
echo "== Stage3 timeout: ${STAGE3_TIMEOUT_SEC}s (0 disables)"
set +e
timeout_marker="$OUT_ROOT/stage3-timeout.marker"
rm -f "$timeout_marker"
HXHX_FORBID_STAGE0=1 HAXE_BIN="$HAXE_SENTINEL" "$HXHX_BIN" "${STAGE3_ARGS[@]}" --hxhx-out "$STAGE3_OUT" >"$STAGE3_LOG" 2>&1 &
stage3_pid=$!
timeout_pid=""
if [ "$STAGE3_TIMEOUT_SEC" -gt 0 ]; then
  (
    elapsed_sec=0
    while kill -0 "$stage3_pid" 2>/dev/null; do
      if [ "$elapsed_sec" -ge "$STAGE3_TIMEOUT_SEC" ]; then
        {
          echo "FAILED: Stage3 scope probe timed out after ${STAGE3_TIMEOUT_SEC}s."
          echo "stage3_timeout_elapsed_sec=$elapsed_sec"
          echo "stage3_timeout_sec=$STAGE3_TIMEOUT_SEC"
        } >>"$STAGE3_LOG"
        append_stage3_timeout_diagnostics
        printf 'timeout\n' >"$timeout_marker"
        pkill -TERM -P "$stage3_pid" 2>/dev/null || true
        kill -TERM "$stage3_pid" 2>/dev/null || true
        sleep 2
        pkill -KILL -P "$stage3_pid" 2>/dev/null || true
        kill -KILL "$stage3_pid" 2>/dev/null || true
        break
      fi
      remaining=$((STAGE3_TIMEOUT_SEC - elapsed_sec))
      if [ "$remaining" -gt 5 ]; then
        sleep_step=5
      elif [ "$remaining" -gt 0 ]; then
        sleep_step="$remaining"
      else
        sleep_step=1
      fi
      sleep "$sleep_step"
      elapsed_sec=$((elapsed_sec + sleep_step))
    done
  ) &
  timeout_pid=$!
fi
wait "$stage3_pid"
stage3_code=$?
if [ -n "$timeout_pid" ]; then
  kill "$timeout_pid" 2>/dev/null || true
  wait "$timeout_pid" 2>/dev/null || true
fi
if [ -s "$timeout_marker" ]; then
  stage3_code=124
fi
set -e

if [ "$stage3_code" -ne 0 ]; then
  echo "FAILED: Stage3 full-body emit probe failed; log: $STAGE3_LOG" >&2
  tail -n 120 "$STAGE3_LOG" >&2 || true
  exit "$stage3_code"
fi

if ! grep -q "^$EXPECTED_MARKER$" "$STAGE3_LOG"; then
  echo "FAILED: Stage3 probe did not emit expected marker: $EXPECTED_MARKER." >&2
  sed -n '1,120p' "$STAGE3_LOG" >&2 || true
  exit 1
fi

generated_ml_count="$(find "$STAGE3_OUT" -type f -name '*.ml' | wc -l | tr -d '[:space:]')"
if [ "$REQUIRE_GENERATED_ML" = "1" ] && [ "$generated_ml_count" = "0" ]; then
  echo "FAILED: Stage3 probe emitted no OCaml source files under $STAGE3_OUT." >&2
  exit 1
fi

artifact_path=""
artifact_validated=0
if [ "$REQUIRE_ARTIFACT" = "1" ]; then
  artifact_path="$(sed -n 's/^exe=//p; s/^artifact=//p' "$STAGE3_LOG" | tail -n 1 | tr -d '\r')"
  if [ -z "$artifact_path" ] || [ ! -f "$artifact_path" ]; then
    echo "FAILED: Stage3 probe did not build the reported artifact." >&2
    sed -n '1,120p' "$STAGE3_LOG" >&2 || true
    exit 1
  fi
  artifact_validated=1
fi

if ! git -C "$ROOT" diff --quiet -- packages/hxhx/bootstrap_out packages/hxhx-macro-host/bootstrap_out; then
  echo "FAILED: bootstrap snapshots changed during probe." >&2
  git -C "$ROOT" status --short -- packages/hxhx/bootstrap_out packages/hxhx-macro-host/bootstrap_out >&2 || true
  exit 1
fi

cat >"$SUMMARY" <<EOF
status=ok
prototype=stage0-free-native-refresh-minimal
decision=native_self_refresh
payload_slicing=rejected_release_equivalence_risk
scope=$SCOPE
target_label=$TARGET_LABEL
stage0_forbidden=1
haxe_bin=$HAXE_SENTINEL
hxhx_bin=$HXHX_BIN
dune_jobs=$DUNE_JOBS_FOR_BUILD
source_inputs=$SOURCE_INPUTS
stage3_out=$STAGE3_OUT
generated_ml_count=$generated_ml_count
artifact_path=$artifact_path
artifact_validated=$artifact_validated
stage3_marker=$EXPECTED_MARKER
stage3_timeout_sec=$STAGE3_TIMEOUT_SEC
bootstrap_snapshot_diff=clean
bootstrap_build_retained=$KEEP_BOOTSTRAP_BUILD
stage3_compiled_artifacts_retained=$KEEP_DUNE_BUILD
build_log=$BUILD_LOG
stage3_log=$STAGE3_LOG
EOF

echo "OK: stage0-free bootstrap refresh probe"
echo "summary=$SUMMARY"
