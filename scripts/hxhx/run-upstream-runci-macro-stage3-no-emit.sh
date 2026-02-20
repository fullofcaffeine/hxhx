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

# Gate 2 stage3 diagnostic still needs `-lib utest` to resolve from `RunCi.hxml`.
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
  local hxml_dir="$UPSTREAM_DIR/tests/haxe_libraries"
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

prepare_haxelib_hxml utest

echo "== Gate 2 (stage3 no-emit rung): upstream tests/RunCi.hxml"
out="$(
  cd "$UPSTREAM_DIR/tests"
  rm -rf out_hxhx_runci_stage3_no_emit
  HAXE_BIN="__disabled__" HAXELIB_BIN="$HAXELIB_BIN" "$HXHX_BIN" --hxhx-stage3 --hxhx-no-emit RunCi.hxml --hxhx-out out_hxhx_runci_stage3_no_emit 2>&1
)"
echo "$out"

echo "$out" | grep -q "^stage3=no_emit_ok$"
