#!/usr/bin/env bash
set -euo pipefail

# Upstream display emit-run smoke (Stage3 full emit, non-delegating).
#
# Goal
# - Run upstream `tests/display/build.hxml` through Stage3 full emit *with execution enabled*.
# - Assert we never regress to segfault-shaped failures while macro API coverage is incomplete.
#
# Current expectation
# - Until full macro API/runtime parity lands, this rung may fail with a deterministic
#   "macro api unavailable" style error.
# - It must not fail as a segmentation fault / EXC_BAD_ACCESS.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"
OUT_NAME="${HXHX_DISPLAY_EMIT_RUN_OUT:-out_hxhx_display_stage3_emit_run}"

if [ ! -d "$UPSTREAM_DIR/tests/display" ]; then
  echo "Skipping upstream display stage3 emit-run smoke: missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream display stage3 emit-run smoke: dune/ocamlc not found on PATH."
  exit 0
fi

if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"

echo "== Upstream display stage3 emit-run smoke"
echo "UPSTREAM_DIR=$UPSTREAM_DIR"
echo "HAXE_STD_PATH=${HAXE_STD_PATH:-}"
echo "HXHX_BIN=$HXHX_BIN"

cd "$UPSTREAM_DIR/tests/display"
tmp_log="$(mktemp)"
trap 'rm -f "$tmp_log"' EXIT

set +e
"$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies build.hxml --hxhx-out "$OUT_NAME" >"$tmp_log" 2>&1
code="$?"
set -e

rg -N "^(resolved_modules|typed_modules|header_only_modules|unsupported_exprs_total|unsupported_files|stage3|run)=" "$tmp_log" || true

if [ "$code" -eq 139 ] || rg -q "Segmentation fault|EXC_BAD_ACCESS" "$tmp_log"; then
  echo "FAILED: display emit-run regressed to segfault-shaped failure (rc=$code)" >&2
  tail -n 200 "$tmp_log" >&2
  exit 1
fi

if [ "$code" -eq 0 ]; then
  rg -q '^run=ok$' "$tmp_log" || {
    echo "FAILED: emit-run exited 0 but missing run=ok marker" >&2
    tail -n 200 "$tmp_log" >&2
    exit 1
  }
  echo "display_stage3_emit_run=ok"
  exit 0
fi

# Bring-up allowance: deterministic, non-crash failure while macro API parity is incomplete.
if rg -q "HxMacroApiUnavailable|macro api unavailable|built executable failed" "$tmp_log"; then
  echo "display_stage3_emit_run=expected_noncrash_failure rc=$code"
  exit 0
fi

echo "FAILED: unexpected non-zero exit (rc=$code) without known safe marker" >&2
tail -n 200 "$tmp_log" >&2
exit 1
