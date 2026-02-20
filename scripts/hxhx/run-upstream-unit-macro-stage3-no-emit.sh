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

# Gate1 now runs widening-enabled by default.
: "${HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES:=1}"
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

prepare_haxelib_hxml() {
  local lib="$1"
  local hxml_dir="$UPSTREAM_DIR/tests/unit/haxe_libraries"
  local hxml_path="$hxml_dir/$lib.hxml"
  local raw_lines=""
  local err_log=""
  local code=0

  mkdir -p "$hxml_dir"
  err_log="$(mktemp)"

  for attempt in 1 2 3; do
    set +e
    raw_lines="$("$HAXELIB_BIN" --always path "$lib" 2>"$err_log")"
    code="$?"
    set -e

    if [ "$code" = "0" ]; then
      break
    fi

    if [ "$code" = "244" ] && [ "$attempt" -lt 3 ]; then
      sleep 1
      continue
    fi

    echo "FAILED: haxelib path $lib exited with code $code" >&2
    cat "$err_log" >&2 || true
    rm -f "$err_log"
    return "$code"
  done

  rm -f "$err_log"

  : > "$hxml_path"
  while IFS= read -r raw; do
    local line
    line="$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ -z "$line" ]; then
      continue
    fi
    case "$line" in
      -D\ *|--macro\ *|-cp\ *|--class-path\ *|-*)
        printf '%s\n' "$line" >> "$hxml_path"
        ;;
      *)
        printf -- '-cp %s\n' "$line" >> "$hxml_path"
        ;;
    esac
  done <<<"$raw_lines"

  if [ ! -s "$hxml_path" ]; then
    echo "FAILED: generated empty haxelib hxml: $hxml_path" >&2
    return 1
  fi
}

if ! has_utest; then
  echo "Installing utest (pinned $UTEST_COMMIT)..."
  "$HAXELIB_BIN" --always git utest https://github.com/haxe-utest/utest "$UTEST_COMMIT"
fi

# Precompute `haxe_libraries/utest.hxml` so Stage3 can resolve `-lib utest` without relying on
# an in-process `haxelib path` call (which can intermittently fail on CI runners).
prepare_haxelib_hxml utest

echo "== Gate 1 (stage3 no-emit rung): upstream tests/unit/compile-macro.hxml"
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

if [ "$code" != "0" ]; then
  echo "FAILED: hxhx stage3 no-emit rung exited with code $code" >&2
  exit "$code"
fi

grep -q "^macro_run\\[0\\]=ok$" <<<"$out"
grep -q "^hook_onGenerate\\[0\\]=ok$" <<<"$out"
grep -q "^stage3=no_emit_ok$" <<<"$out"

test ! -f "$UPSTREAM_DIR/tests/unit/out_hxhx_unit_macro_stage3_no_emit/out.exe"
