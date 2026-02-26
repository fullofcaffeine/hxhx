#!/usr/bin/env bash
set -euo pipefail

# M14 benchmark harness (runtime + compiler-shaped workloads).
#
# Records results to `bench/results/` as JSON so we can track regressions over time.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

HAXE_BIN="${HAXE_BIN:-haxe}"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping M14 benchmarks: dune/ocamlc not found on PATH."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Missing python3 on PATH (required for the benchmark timer)." >&2
  exit 1
fi

mkdir -p "$ROOT/bench/results"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_file="$ROOT/bench/results/m14-$timestamp.json"
latest_file="$ROOT/bench/results/m14-latest.json"

reps="${M14_BENCH_REPS:-10}"
compile_reps="${M14_BENCH_COMPILE_REPS:-3}"
stringbuf_n="${M14_STRINGBUF_N:-200000}"
int_array_n="${M14_INT_ARRAY_N:-50000}"
anon_iterations="${M14_ANON_ITERATIONS:-300000}"
profiles="${M14_PROFILES:-portable,metal}"
runtime_mode="${M14_RUNTIME_MODE:-full}"

python3 "$ROOT/scripts/bench/m14.py" \
  --haxe-bin "$HAXE_BIN" \
  --reps "$reps" \
  --compile-reps "$compile_reps" \
  --profiles "$profiles" \
  --runtime-mode "$runtime_mode" \
  --stringbuf-n "$stringbuf_n" \
  --int-array-n "$int_array_n" \
  --anon-iterations "$anon_iterations" \
  --out "$out_file"

cp "$out_file" "$latest_file"

echo "Wrote:  $out_file"
echo "Latest: $latest_file"
