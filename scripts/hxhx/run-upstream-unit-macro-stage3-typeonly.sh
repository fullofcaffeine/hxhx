#!/usr/bin/env bash
set -euo pipefail

# Gate 1 diagnostic rung (Stage3 typer, type-only).
#
# Goal
# - Run `hxhx --hxhx-stage3 --hxhx-type-only` against upstream `tests/unit/compile-macro.hxml`
#   without delegating to stage0 `haxe`.
#
# Notes
# - This does NOT execute macros. In Stage3 type-only mode we intentionally skip `--macro`
#   directives so this can be used to measure typer coverage without requiring a macro host.
# - This does not emit OCaml or build an executable.

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"
UPSTREAM_REF="${HAXE_UPSTREAM_REF:-4.3.7}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests/unit" ]; then
  echo "Skipping upstream Gate 1 (stage3 type-only): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
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
  echo "Skipping upstream Gate 1 (stage3 type-only): dune/ocamlc not found on PATH."
  exit 0
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh")"

# Stage3 relies on an explicit std root.
#
# Prefer upstream's `std/` when available, because `haxe` can be a shim (e.g. lix)
# that doesn't sit next to a `std` folder on disk.
if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

# Otherwise, try inferring it from the stage0 `haxe` binary.
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

echo "== Gate 1 (stage3 type-only rung): upstream tests/unit/compile-macro.hxml"
out="$(
  cd "$UPSTREAM_DIR/tests/unit"
  HAXE_BIN="$HAXE_BIN" HAXELIB_BIN="$HAXELIB_BIN" "$HXHX_BIN" --hxhx-stage3 --hxhx-type-only compile-macro.hxml --hxhx-out out_hxhx_unit_macro_stage3_typeonly 2>&1
)"
echo "$out"

echo "$out" | grep -q "^stage3=type_only_ok$"
