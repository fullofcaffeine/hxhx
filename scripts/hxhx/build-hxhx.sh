#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXAMPLE_DIR="$ROOT/examples/hxhx"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping hxhx build: dune/ocamlc not found on PATH."
  exit 0
fi

if [ ! -d "$EXAMPLE_DIR" ]; then
  echo "Missing hxhx example directory: $EXAMPLE_DIR" >&2
  exit 1
fi

(
  cd "$EXAMPLE_DIR"
  rm -rf out
  mkdir -p out
  "$HAXE_BIN" build.hxml -D ocaml_build=native
)

BIN="$EXAMPLE_DIR/out/_build/default/out.exe"
if [ ! -f "$BIN" ]; then
  echo "Missing built executable: $BIN" >&2
  exit 1
fi

echo "$BIN"

