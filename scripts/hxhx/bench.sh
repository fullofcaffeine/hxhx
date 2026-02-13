#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

HAXE_BIN="${HAXE_BIN:-haxe}"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping hxhx bench: dune/ocamlc not found on PATH."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Missing python3 on PATH (required for the benchmark timer)." >&2
  exit 1
fi

reps="${HXHX_BENCH_REPS:-10}"

HXHX_BIN="${HXHX_BIN:-}"
if [ -z "$HXHX_BIN" ]; then
  HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
fi
if [ -z "$HXHX_BIN" ] || [ ! -f "$HXHX_BIN" ]; then
  echo "Missing hxhx stage1 binary (set HXHX_BIN or ensure build-hxhx.sh works)." >&2
  exit 1
fi

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root" >/dev/null 2>&1 || true' EXIT

mkdir -p "$tmp_root/src"
cat >"$tmp_root/src/Main.hx" <<'HX'
class Main {
  static function main() {
    // keep it non-empty so the compiler can't short-circuit everything
    Sys.println("OK bench");
  }
}
HX

bench_one() {
  local label="$1"
  shift

  local total_ms=0
  local best_ms=999999999
  local worst_ms=0

  for i in $(seq 1 "$reps"); do
    local start end dt_ms
    start="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"
    "$@" >/dev/null 2>&1
    end="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"
    dt_ms=$((end - start))
    total_ms=$((total_ms + dt_ms))
    if [ "$dt_ms" -lt "$best_ms" ]; then best_ms="$dt_ms"; fi
    if [ "$dt_ms" -gt "$worst_ms" ]; then worst_ms="$dt_ms"; fi
  done

  local avg_ms=$((total_ms / reps))
  printf '%-32s avg=%6sms  best=%6sms  worst=%6sms  reps=%s\n' "$label" "$avg_ms" "$best_ms" "$worst_ms" "$reps"
}

echo "== hxhx bench (stage0 shim + builtin fast-path)"
echo "Platform: $(uname -s) $(uname -m)"
echo "Stage0 haxe: $("$HAXE_BIN" -version 2>/dev/null || "$HAXE_BIN" --version 2>/dev/null || echo unknown)"
echo "Stage1 hxhx: $HXHX_BIN"
echo "Reps: $reps"
echo ""

bench_one "stage0: haxe --version" "$HAXE_BIN" --version
bench_one "stage1: hxhx --version" "$HXHX_BIN" --version

bench_one "stage0: no-output compile" \
  "$HAXE_BIN" -cp "$tmp_root/src" -main Main --no-output

bench_one "stage1: no-output compile" \
  "$HXHX_BIN" -cp "$tmp_root/src" -main Main --no-output

bench_one "stage1: --target ocaml-stage3" \
  "$HXHX_BIN" --target ocaml-stage3 --hxhx-no-emit -cp "$tmp_root/src" -main Main --hxhx-out "$tmp_root/out_stage3_builtin"

echo ""
echo "NOTE: --target ocaml still delegates to stage0, while --target ocaml-stage3 exercises the linked Stage3 backend fast-path."
