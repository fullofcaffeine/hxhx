#!/usr/bin/env bash
set -euo pipefail

# Gate 2 diagnostic rung (Stage3 no-emit).
#
# Goal
# - Resolve + type the upstream RunCi module graph (and run any CLI macros if present),
#   but skip OCaml emission/build.
#
# Notes
# - This is still far from “Gate2 acceptance” (executing the runci Macro target), but it
#   gives a stable place to measure Stage3 parser+typer progress on upstream harness code.

HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests" ] || [ ! -f "$UPSTREAM_DIR/tests/RunCi.hxml" ]; then
  echo "Skipping upstream Gate 2 (stage3 no-emit): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v "$HAXELIB_BIN" >/dev/null 2>&1; then
  echo "Missing haxelib on PATH (expected '$HAXELIB_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream Gate 2 (stage3 no-emit): dune/ocamlc not found on PATH."
  exit 0
fi

# Prefer upstream's `std/` for deterministic resolution.
if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

if [ -z "${HAXE_STD_PATH:-}" ]; then
  echo "Skipping upstream Gate 2 (stage3 no-emit): missing std classpath (set HAXE_STD_PATH or provide upstream std/)." >&2
  exit 0
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"

echo "== Gate 2 (stage3 no-emit rung): upstream tests/RunCi.hxml"
out="$(
  cd "$UPSTREAM_DIR/tests"
  rm -rf out_hxhx_runci_stage3_no_emit
  HAXE_BIN="__disabled__" HAXELIB_BIN="$HAXELIB_BIN" "$HXHX_BIN" --hxhx-stage3 --hxhx-no-emit RunCi.hxml --hxhx-out out_hxhx_runci_stage3_no_emit 2>&1
)"
echo "$out"

echo "$out" | grep -q "^stage3=no_emit_ok$"

