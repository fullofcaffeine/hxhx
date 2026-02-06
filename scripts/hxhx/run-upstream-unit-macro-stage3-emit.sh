#!/usr/bin/env bash
set -euo pipefail

# Gate 1 diagnostic rung (Stage3 emit+build+run).
#
# Goal
# - Execute upstream `--macro` directives + hooks, and run the Stage3 typer over the resolved module graph,
#   then emit a bootstrap OCaml program and run it.
#
# Why
# - This is a bring-up rung between "type-only/no-emit" and true Gate1 acceptance.
# - The Stage3 emitter is still non-semantic (lots of `Obj.magic`), but this validates:
#   - macro execution path (Stage4 host),
#   - OCaml emission/build wiring,
#   - and that we don't crash on upstream-shaped inputs.

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests/unit" ]; then
  echo "Skipping upstream Gate 1 (stage3 emit): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
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
  echo "Skipping upstream Gate 1 (stage3 emit): dune/ocamlc not found on PATH."
  exit 0
fi

# Prefer upstream's `std/` for deterministic resolution (works even when `haxe` is a shim like lix).
if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh")"

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

echo "== Gate 1 (stage3 emit rung): upstream tests/unit/compile-macro.hxml"
out="$(
  cd "$UPSTREAM_DIR/tests/unit"
  rm -rf out_hxhx_unit_macro_stage3_emit
  HXHX_MACRO_HOST_AUTO_BUILD=1 \
    HAXE_BIN="$HAXE_BIN" HAXELIB_BIN="$HAXELIB_BIN" \
    "$HXHX_BIN" --hxhx-stage3 compile-macro.hxml --hxhx-out out_hxhx_unit_macro_stage3_emit 2>&1
)"
echo "$out"

echo "$out" | grep -q "^macro_run\\[0\\]=ok$"
echo "$out" | grep -q "^hook_onGenerate\\[0\\]=ok$"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^run=ok$"

