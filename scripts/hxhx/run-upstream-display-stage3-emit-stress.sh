#!/usr/bin/env bash
set -euo pipefail

# Upstream display stress rung (Stage3 emit + no-run).
#
# Why
# - `tests/display/build.hxml` is a realistic compiler-shaped workload with broad module coverage.
# - Stage3 had a warm-output flake where run N could omit providers that were present in run N-1.
# - This stress rung validates repeated full-emit invocations against the same `--hxhx-out` directory.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"
ITERATIONS="${HXHX_DISPLAY_EMIT_STRESS_ITERS:-10}"
OUT_NAME="${HXHX_DISPLAY_EMIT_STRESS_OUT:-out_hxhx_display_stage3_emit_stress}"

if [ ! -d "$UPSTREAM_DIR/tests/display" ]; then
  echo "Skipping upstream display stage3 emit stress: missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream display stage3 emit stress: dune/ocamlc not found on PATH."
  exit 0
fi

if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"

echo "== Upstream display stage3 emit stress"
echo "UPSTREAM_DIR=$UPSTREAM_DIR"
echo "HAXE_STD_PATH=${HAXE_STD_PATH:-}"
echo "HXHX_BIN=$HXHX_BIN"
echo "ITERATIONS=$ITERATIONS"

cd "$UPSTREAM_DIR/tests/display"
rm -rf "$OUT_NAME"

for i in $(seq 1 "$ITERATIONS"); do
  echo "== display stage3 emit iter $i/$ITERATIONS =="
  tmp_log="$(mktemp)"
  set +e
  "$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run build.hxml --hxhx-out "$OUT_NAME" >"$tmp_log" 2>&1
  code="$?"
  set -e
  rg -N "^(resolved_modules|typed_modules|header_only_modules|unsupported_exprs_total|unsupported_files|stage3|run)=" "$tmp_log" || true
  if [ "$code" -ne 0 ]; then
    echo "FAILED: iter $i/$ITERATIONS exited with code $code" >&2
    tail -n 160 "$tmp_log" >&2
    rm -f "$tmp_log"
    exit "$code"
  fi
  if ! rg -q '^stage3=ok$' "$tmp_log"; then
    echo "FAILED: iter $i/$ITERATIONS missing stage3=ok" >&2
    tail -n 160 "$tmp_log" >&2
    rm -f "$tmp_log"
    exit 1
  fi
  if ! rg -q '^run=skipped$' "$tmp_log"; then
    echo "FAILED: iter $i/$ITERATIONS missing run=skipped" >&2
    tail -n 160 "$tmp_log" >&2
    rm -f "$tmp_log"
    exit 1
  fi
  rm -f "$tmp_log"
done

echo "display_stage3_emit_stress=ok iterations=$ITERATIONS"
