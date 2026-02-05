#!/usr/bin/env bash
set -euo pipefail

# Gate 1 bring-up rung (Stage1).
#
# Goal
# - Prove Stage1 (non-shim) can parse + resolve the upstream unit macro suite entrypoint
#   without delegating to stage0 `haxe`.
#
# Notes
# - This does NOT run the unit tests. It only validates CLI parsing, hxml expansion,
#   -lib classpath resolution, and import-closure parsing via the native frontend seam.

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"
UPSTREAM_REF="${HAXE_UPSTREAM_REF:-4.3.7}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests/unit" ]; then
  echo "Skipping upstream Gate 1 (stage1): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v "$HAXELIB_BIN" >/dev/null 2>&1; then
  echo "Missing haxelib on PATH (expected '$HAXELIB_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream Gate 1 (stage1): dune/ocamlc not found on PATH."
  exit 0
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh")"

# Stage1 bring-up relies on an explicit std root. Prefer inferring it from the stage0 `haxe` binary.
if [ -z "${HAXE_STD_PATH:-}" ]; then
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

# Gate 1 depends on `-lib utest`. Upstream CI pins utest; match the pin so fixture content stays stable.
UTEST_COMMIT="a94f8812e8786f2b5fec52ce9f26927591d26327"
has_utest() {
  if command -v rg >/dev/null 2>&1; then
    "$HAXELIB_BIN" list 2>/dev/null | rg -q "^utest:"
  else
    "$HAXELIB_BIN" list 2>/dev/null | grep -q "^utest:"
  fi
}

if ! has_utest; then
  echo "Installing utest (pinned $UTEST_COMMIT)..."
  "$HAXELIB_BIN" --always git utest https://github.com/haxe-utest/utest "$UTEST_COMMIT"
fi

echo "== Gate 1 (stage1 rung): upstream tests/unit/compile-macro.hxml (parse+resolve; no output)"
out="$(
  cd "$UPSTREAM_DIR/tests/unit"
  HAXE_BIN="$HAXE_BIN" HAXELIB_BIN="$HAXELIB_BIN" "$HXHX_BIN" --hxhx-stage1 --hxhx-permissive compile-macro.hxml --no-output 2>&1
)"
echo "$out"

echo "$out" | grep -q "^stage1=ok$"
