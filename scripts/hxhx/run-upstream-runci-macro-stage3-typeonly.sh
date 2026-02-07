#!/usr/bin/env bash
set -euo pipefail

# Gate 2 diagnostic rung (Stage3 type-only).
#
# Goal
# - Resolve + type the upstream RunCi module graph without delegating to stage0 `haxe`.
#
# Notes
# - This intentionally skips macro execution (`--hxhx-type-only`), because Gate2 needs
#   to separate “typer coverage” from “macro host semantics”.

HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests" ] || [ ! -f "$UPSTREAM_DIR/tests/RunCi.hxml" ]; then
  echo "Skipping upstream Gate 2 (stage3 type-only): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v "$HAXELIB_BIN" >/dev/null 2>&1; then
  echo "Missing haxelib on PATH (expected '$HAXELIB_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream Gate 2 (stage3 type-only): dune/ocamlc not found on PATH."
  exit 0
fi

# Prefer upstream's `std/` for deterministic resolution.
if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

if [ -z "${HAXE_STD_PATH:-}" ]; then
  echo "Skipping upstream Gate 2 (stage3 type-only): missing std classpath (set HAXE_STD_PATH or provide upstream std/)." >&2
  exit 0
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh")"

echo "== Gate 2 (stage3 type-only rung): upstream tests/RunCi.hxml"
out="$(
  cd "$UPSTREAM_DIR/tests"
  rm -rf out_hxhx_runci_stage3_typeonly
  HAXE_BIN="__disabled__" HAXELIB_BIN="$HAXELIB_BIN" "$HXHX_BIN" --hxhx-stage3 --hxhx-type-only RunCi.hxml --hxhx-out out_hxhx_runci_stage3_typeonly 2>&1
)"
echo "$out"

echo "$out" | grep -q "^unsupported_exprs_total=0$"
echo "$out" | grep -q "^unsupported_files=0$"
echo "$out" | grep -q "^stage3=type_only_ok$"
