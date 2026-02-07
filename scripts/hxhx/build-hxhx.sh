#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
HXHX_FORCE_STAGE0="${HXHX_FORCE_STAGE0:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HXHX_DIR="$ROOT/packages/hxhx"
BOOTSTRAP_DIR="$HXHX_DIR/bootstrap_out"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping hxhx build: dune/ocamlc not found on PATH."
  exit 0
fi

if [ ! -d "$HXHX_DIR" ]; then
  echo "Missing hxhx package directory: $HXHX_DIR" >&2
  exit 1
fi

if [ -z "$HXHX_FORCE_STAGE0" ] && [ -d "$BOOTSTRAP_DIR" ] && [ -f "$BOOTSTRAP_DIR/dune" ]; then
  (
    cd "$BOOTSTRAP_DIR"
    dune build
  )

  BIN="$BOOTSTRAP_DIR/_build/default/out.exe"
  if [ ! -f "$BIN" ]; then
    echo "Missing built executable: $BIN" >&2
    exit 1
  fi

  echo "$BIN"
  exit 0
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

(
  cd "$HXHX_DIR"
  rm -rf out
  mkdir -p out
  "$HAXE_BIN" build.hxml -D ocaml_build=native
)

BIN="$HXHX_DIR/out/_build/default/out.exe"
if [ ! -f "$BIN" ]; then
  echo "Missing built executable: $BIN" >&2
  exit 1
fi

echo "$BIN"
