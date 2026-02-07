#!/usr/bin/env bash
set -euo pipefail

# Gate 2 bring-up rung (Stage1).
#
# Goal
# - Prove Stage1 (non-shim) can parse + resolve the upstream RunCi entrypoint
#   without delegating to stage0 `haxe`.
#
# Notes
# - This does NOT execute the runci Macro target. It only validates CLI parsing,
#   `.hxml` expansion, std classpath inference, and import-closure parsing.

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"
UPSTREAM_REF="${HAXE_UPSTREAM_REF:-4.3.7}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests" ] || [ ! -f "$UPSTREAM_DIR/tests/RunCi.hxml" ]; then
  echo "Skipping upstream Gate 2 (stage1): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v "$HAXELIB_BIN" >/dev/null 2>&1; then
  echo "Missing haxelib on PATH (expected '$HAXELIB_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream Gate 2 (stage1): dune/ocamlc not found on PATH."
  exit 0
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh")"

# Stage1 bring-up relies on an explicit std root. Prefer upstream `std/` for deterministic resolution.
if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

# If upstream std isn't present, infer it from the stage0 toolchain (best-effort).
if [ -z "${HAXE_STD_PATH:-}" ] && command -v "$HAXE_BIN" >/dev/null 2>&1; then
  stage0_haxe=""
  if [ -x "$HOME/haxe/versions/$UPSTREAM_REF/haxe" ]; then
    stage0_haxe="$HOME/haxe/versions/$UPSTREAM_REF/haxe"
  else
    stage0_haxe="$(command -v "$HAXE_BIN" 2>/dev/null || true)"
  fi
  if [ -n "$stage0_haxe" ]; then
    stage0_dir="$(cd "$(dirname "$stage0_haxe")" && pwd)"
    if [ -d "$stage0_dir/std" ]; then
      export HAXE_STD_PATH="$stage0_dir/std"
    fi
  fi
fi

if [ -z "${HAXE_STD_PATH:-}" ]; then
  echo "Skipping upstream Gate 2 (stage1): missing std classpath (set HAXE_STD_PATH or provide upstream std/)." >&2
  exit 0
fi

echo "== Gate 2 (stage1 rung): upstream tests/RunCi.hxml (parse+resolve; no output)"
out="$(
  cd "$UPSTREAM_DIR/tests"
  HAXE_BIN="__disabled__" HAXELIB_BIN="$HAXELIB_BIN" "$HXHX_BIN" --hxhx-stage1 --hxhx-permissive RunCi.hxml --no-output 2>&1
)"
echo "$out"

echo "$out" | grep -q "^stage1=ok$"

