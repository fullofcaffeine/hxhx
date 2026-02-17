#!/usr/bin/env bash
set -euo pipefail

# Gate 1 macro/model diagnostic rung (Stage3 no-emit).
#
# Goal
# - Execute upstream `--macro` directives + hooks, and run the Stage3 typer over the resolved module graph,
#   but skip OCaml emission/build.
#
# Why
# - This lets us iterate Stage4 macro execution model + Stage3 typer coverage without being blocked by the
#   bootstrap emitter's limited codegen.

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

# Deterministic Gate1 resolver profile.
#
# Why
# - The implicit same-package widening heuristic is useful in broader bring-up workloads,
#   but it currently widens compile-macro.hxml enough to hit a Darwin-only native crash path.
# - Gate1's compile-macro acceptance does not require that heuristic.
#
# Override
# - Set HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES=1 to opt back in for local debugging.
: "${HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES:=0}"
export HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES

if [ ! -d "$UPSTREAM_DIR/tests/unit" ]; then
  echo "Skipping upstream Gate 1 (stage3 no-emit): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
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
  echo "Skipping upstream Gate 1 (stage3 no-emit): dune/ocamlc not found on PATH."
  exit 0
fi

# Prefer upstream's `std/` for deterministic resolution (works even when `haxe` is a shim like lix).
if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"

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

echo "== Gate 1 (stage3 no-emit rung): upstream tests/unit/compile-macro.hxml"
attempt=1
max_attempts=2
while true; do
  set +e
  out="$(
    cd "$UPSTREAM_DIR/tests/unit"
    rm -rf out_hxhx_unit_macro_stage3_no_emit
    HXHX_MACRO_HOST_AUTO_BUILD=1 \
      HAXE_BIN="$HAXE_BIN" HAXELIB_BIN="$HAXELIB_BIN" \
      "$HXHX_BIN" --hxhx-stage3 --hxhx-no-emit compile-macro.hxml --hxhx-out out_hxhx_unit_macro_stage3_no_emit 2>&1
  )"
  code="$?"
  set -e
  echo "$out"

  if [ "$code" = "0" ]; then
    break
  fi

  if [ "$code" = "139" ] && [ "$(uname -s)" = "Darwin" ] && [ "$attempt" -lt "$max_attempts" ]; then
    echo "Retrying stage3 no-emit rung after Darwin SIGSEGV (attempt $attempt/$max_attempts)." >&2
    attempt=$((attempt + 1))
    continue
  fi

  echo "FAILED: hxhx stage3 no-emit rung exited with code $code" >&2
  exit "$code"
done

grep -q "^macro_run\\[0\\]=ok$" <<<"$out"
grep -q "^hook_onGenerate\\[0\\]=ok$" <<<"$out"
grep -q "^stage3=no_emit_ok$" <<<"$out"

test ! -f "$UPSTREAM_DIR/tests/unit/out_hxhx_unit_macro_stage3_no_emit/out.exe"
