#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXAMPLE_DIR="$ROOT/packages/reflaxe.ocaml/examples/hxhx-native-reflaxe-bench"

HAXE_BIN="${HAXE_BIN:-haxe}"
HXHX_BIN="${HXHX_BIN:-}"

REPS="${HXHX_NATIVE_BENCH_REPS:-9}"
ITERS="${HXHX_BENCH_ITERS:-200000}"
MIN_SPEEDUP_PCT="${HXHX_NATIVE_BENCH_MIN_SPEEDUP_PCT:-30}"
BASELINE_MODE="${HXHX_NATIVE_BENCH_BASELINE:-interp}" # interp|delegated|both

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping native reflaxe bench: dune/ocamlc not found on PATH."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Missing python3 on PATH (required for timing/statistics)." >&2
  exit 1
fi

if [ ! -d "$EXAMPLE_DIR" ]; then
  echo "Missing benchmark example directory: $EXAMPLE_DIR" >&2
  exit 1
fi

if [ -z "$HXHX_BIN" ]; then
  HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
fi
if [ -z "$HXHX_BIN" ] || [ ! -f "$HXHX_BIN" ]; then
  echo "Missing hxhx binary (set HXHX_BIN or ensure build-hxhx.sh works)." >&2
  exit 1
fi

now_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

measure_fn_ms() {
  local fn="$1"
  local start end
  start="$(now_ms)"
  "$fn"
  end="$(now_ms)"
  echo "$((end - start))"
}

median_ms() {
  python3 - "$@" <<'PY'
import sys
values = sorted(int(v) for v in sys.argv[1:])
if not values:
    print(0)
    raise SystemExit(0)
n = len(values)
mid = n // 2
if n % 2 == 1:
    print(values[mid])
else:
    print((values[mid - 1] + values[mid]) // 2)
PY
}

p95_ms() {
  python3 - "$@" <<'PY'
import math
import sys
values = sorted(int(v) for v in sys.argv[1:])
if not values:
    print(0)
    raise SystemExit(0)
idx = max(0, min(len(values) - 1, math.ceil(0.95 * len(values)) - 1))
print(values[idx])
PY
}

speedup_pct() {
  local baseline="$1"
  local candidate="$2"
  python3 - "$baseline" "$candidate" <<'PY'
import sys
b = float(sys.argv[1])
c = float(sys.argv[2])
if b <= 0:
    print("0.0")
else:
    print(f"{((b - c) / b) * 100.0:.1f}")
PY
}

compile_delegated() {
  (
    cd "$EXAMPLE_DIR"
    HXHX_REPO_ROOT="$ROOT" HAXE_BIN="$HAXE_BIN" "$HXHX_BIN" --target ocaml build.hxml -D ocaml_build=native >/dev/null 2>&1
  )
}

compile_stage3() {
  (
    cd "$ROOT"
    HXHX_FORBID_STAGE0=1 HXHX_REPO_ROOT="$ROOT" HAXE_BIN="$HAXE_BIN" "$HXHX_BIN" \
      --target ocaml-stage3 \
      --hxhx-no-run \
      --hxhx-emit-full-bodies \
      --hxhx-out "$EXAMPLE_DIR/out_stage3" \
      "$EXAMPLE_DIR/build.hxml" \
      -D ocaml_build=native >/dev/null 2>&1
  )
}

run_interp_once() {
  (
    cd "$EXAMPLE_DIR"
    HXHX_BENCH_ITERS="$ITERS" "$HAXE_BIN" interp.hxml >/dev/null
  )
}

run_delegated_once() {
  HXHX_BENCH_ITERS="$ITERS" "$EXAMPLE_DIR/out/_build/default/out.exe" >/dev/null
}

run_stage3_once() {
  HXHX_BENCH_ITERS="$ITERS" "$EXAMPLE_DIR/out_stage3/out.exe" >/dev/null
}

capture_interp() {
  (
    cd "$EXAMPLE_DIR"
    HXHX_BENCH_ITERS="$ITERS" "$HAXE_BIN" interp.hxml
  )
}

capture_delegated() {
  HXHX_BENCH_ITERS="$ITERS" "$EXAMPLE_DIR/out/_build/default/out.exe"
}

capture_stage3() {
  HXHX_BENCH_ITERS="$ITERS" "$EXAMPLE_DIR/out_stage3/out.exe"
}

bench_lane() {
  local label="$1"
  local fn="$2"
  local -a samples=()
  local best=999999999
  local worst=0
  local total=0

  for _ in $(seq 1 "$REPS"); do
    local ms
    ms="$(measure_fn_ms "$fn")"
    samples+=("$ms")
    total=$((total + ms))
    if [ "$ms" -lt "$best" ]; then best="$ms"; fi
    if [ "$ms" -gt "$worst" ]; then worst="$ms"; fi
  done

  local median p95 avg
  median="$(median_ms "${samples[@]}")"
  p95="$(p95_ms "${samples[@]}")"
  avg=$((total / REPS))

  printf '%-40s median=%6sms  p95=%6sms  avg=%6sms  best=%6sms  worst=%6sms  reps=%s\n' \
    "$label" "$median" "$p95" "$avg" "$best" "$worst" "$REPS" >&2
  echo "$median"
}

rm -rf "$EXAMPLE_DIR/out" "$EXAMPLE_DIR/out_stage3"

echo "== hxhx native reflaxe benchmark"
echo "Workload: $EXAMPLE_DIR"
echo "Stage0 (plain words): existing installed haxe compiler."
echo "ocaml target: preset/delegation-friendly path."
echo "ocaml-stage3 target: linked Stage3 backend path (no stage0 delegation in this lane)."
echo "HXHX_BIN: $HXHX_BIN"
echo "HAXE_BIN: $HAXE_BIN"
echo "Iterations per run: $ITERS"
echo "Benchmark reps per lane: $REPS"
echo "Speed gate baseline mode: $BASELINE_MODE"
echo "Minimum speedup percent: $MIN_SPEEDUP_PCT"
echo ""

delegate_compile_ms="$(measure_fn_ms compile_delegated)"
stage3_compile_ms="$(measure_fn_ms compile_stage3)"

if [ ! -f "$EXAMPLE_DIR/out/_build/default/out.exe" ]; then
  echo "Missing delegated benchmark executable." >&2
  exit 1
fi
if [ ! -f "$EXAMPLE_DIR/out_stage3/out.exe" ]; then
  echo "Missing stage3 benchmark executable." >&2
  exit 1
fi

echo "Compile timings (single shot):"
echo "  delegated (target ocaml): ${delegate_compile_ms}ms"
echo "  stage3 (target ocaml-stage3): ${stage3_compile_ms}ms"
echo ""

interp_out="$(capture_interp)"
delegated_out="$(capture_delegated)"
stage3_out="$(capture_stage3)"
if [ "$interp_out" != "$delegated_out" ] || [ "$interp_out" != "$stage3_out" ]; then
  echo "Benchmark workload output mismatch between lanes." >&2
  echo "--- interp ---" >&2
  printf '%s\n' "$interp_out" >&2
  echo "--- delegated ---" >&2
  printf '%s\n' "$delegated_out" >&2
  echo "--- stage3 ---" >&2
  printf '%s\n' "$stage3_out" >&2
  exit 1
fi

echo "Runtime timings (same workload, higher = slower):"
interp_median="$(bench_lane "stage0 eval baseline: haxe --interp" run_interp_once)"
delegated_median="$(bench_lane "hxhx --target ocaml (delegated preset)" run_delegated_once)"
stage3_median="$(bench_lane "hxhx --target ocaml-stage3 (native)" run_stage3_once)"
echo ""

speed_interp="$(speedup_pct "$interp_median" "$stage3_median")"
speed_delegated="$(speedup_pct "$delegated_median" "$stage3_median")"

echo "Speedup summary (stage3 vs baseline):"
echo "  vs interp:   ${speed_interp}%"
echo "  vs delegated:${speed_delegated}%"
echo ""

compare_threshold() {
  local actual="$1"
  local expected="$2"
  python3 - "$actual" "$expected" <<'PY'
import sys
actual = float(sys.argv[1])
expected = float(sys.argv[2])
print("1" if actual >= expected else "0")
PY
}

fail=0
case "$BASELINE_MODE" in
  interp)
    if [ "$(compare_threshold "$speed_interp" "$MIN_SPEEDUP_PCT")" != "1" ]; then
      echo "FAIL: stage3 speedup vs interp (${speed_interp}%) is below ${MIN_SPEEDUP_PCT}%." >&2
      fail=1
    fi
    ;;
  delegated)
    if [ "$(compare_threshold "$speed_delegated" "$MIN_SPEEDUP_PCT")" != "1" ]; then
      echo "FAIL: stage3 speedup vs delegated (${speed_delegated}%) is below ${MIN_SPEEDUP_PCT}%." >&2
      fail=1
    fi
    ;;
  both)
    if [ "$(compare_threshold "$speed_interp" "$MIN_SPEEDUP_PCT")" != "1" ]; then
      echo "FAIL: stage3 speedup vs interp (${speed_interp}%) is below ${MIN_SPEEDUP_PCT}%." >&2
      fail=1
    fi
    if [ "$(compare_threshold "$speed_delegated" "$MIN_SPEEDUP_PCT")" != "1" ]; then
      echo "FAIL: stage3 speedup vs delegated (${speed_delegated}%) is below ${MIN_SPEEDUP_PCT}%." >&2
      fail=1
    fi
    ;;
  *)
    echo "Invalid HXHX_NATIVE_BENCH_BASELINE='$BASELINE_MODE' (expected interp|delegated|both)." >&2
    exit 2
    ;;
esac

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "PASS native reflaxe speed gate"
