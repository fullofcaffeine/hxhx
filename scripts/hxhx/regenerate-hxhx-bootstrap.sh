#!/usr/bin/env bash
set -euo pipefail

# Regenerate the committed bootstrap snapshot for `hxhx` itself.
#
# Why
# - CI/Gate runners should be able to build `hxhx` without requiring a stage0 `haxe` binary.
# - We achieve this by committing a generated OCaml snapshot under `packages/hxhx/bootstrap_out`
#   and building it with `dune`.
#
# What
# - Builds `packages/hxhx` via stage0 `haxe` + `reflaxe.ocaml`.
# - Copies the generated OCaml sources (excluding `_build/` and `_gen_hx/`) into:
#     packages/hxhx/bootstrap_out/
#
# Notes
# - Maintainer-only script: it requires stage0 `haxe`.
# - Do not edit files inside `packages/hxhx/bootstrap_out/` by hand.

HAXE_BIN="${HAXE_BIN:-haxe}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="$ROOT/packages/hxhx"
OUT_DIR="$PKG_DIR/out"
BOOTSTRAP_DIR="$PKG_DIR/bootstrap_out"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Missing dune/ocamlc on PATH." >&2
  exit 1
fi

if [ ! -d "$PKG_DIR" ]; then
  echo "Missing package directory: $PKG_DIR" >&2
  exit 1
fi

echo "== Regenerating hxhx via stage0 (this requires Haxe + reflaxe.ocaml)"
(
  cd "$ROOT"
  HXHX_FORCE_STAGE0=1 \
  bash "$ROOT/scripts/hxhx/build-hxhx.sh" >/dev/null
)

if [ ! -d "$OUT_DIR" ]; then
  echo "Missing generated output directory: $OUT_DIR" >&2
  exit 1
fi

echo "== Updating bootstrap snapshot: $BOOTSTRAP_DIR"
rm -rf "$BOOTSTRAP_DIR"
mkdir -p "$BOOTSTRAP_DIR"

# Copy everything except build artifacts and generator sources.
(cd "$OUT_DIR" && tar --exclude='_build' --exclude='_gen_hx' -cf - .) | (cd "$BOOTSTRAP_DIR" && tar -xf -)

echo "OK: regenerated bootstrap snapshot"

