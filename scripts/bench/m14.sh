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

python3 "$ROOT/scripts/bench/m14.py" \
  --haxe-bin "$HAXE_BIN" \
  --reps "$reps" \
  --compile-reps "$compile_reps" \
  --stringbuf-n "$stringbuf_n" \
  --out "$out_file"

cp "$out_file" "$latest_file"

echo "Wrote:  $out_file"
echo "Latest: $latest_file"
