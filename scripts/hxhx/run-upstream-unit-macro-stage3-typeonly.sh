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

# Gate1 now runs widening-enabled by default.
: "${HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES:=1}"
export HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES

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

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"

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

echo "== Gate 1 (stage3 type-only rung): upstream tests/unit/compile-macro.hxml"
set +e
out="$(
  cd "$UPSTREAM_DIR/tests/unit"
  HAXE_BIN="$HAXE_BIN" HAXELIB_BIN="$HAXELIB_BIN" "$HXHX_BIN" --hxhx-stage3 --hxhx-type-only compile-macro.hxml --hxhx-out out_hxhx_unit_macro_stage3_typeonly 2>&1
)"
code="$?"
set -e
echo "$out"

if [ "$code" != "0" ]; then
  echo "FAILED: hxhx stage3 type-only rung exited with code $code" >&2
  exit "$code"
fi

grep -q "^stage3=type_only_ok$" <<<"$out"
