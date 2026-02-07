#!/usr/bin/env bash
set -euo pipefail

# Regenerate the committed Stage4 bootstrap snapshot for `hxhx-macro-host`.
#
# Why
# - CI and Gate runners should be able to build/select a macro host without a stage0 `haxe`
#   binary, using `tools/hxhx-macro-host/bootstrap_out`.
# - When macro-host Haxe sources change, we update the snapshot intentionally via this script.
#
# What
# - Builds `tools/hxhx-macro-host` via stage0 `haxe` + `reflaxe.ocaml`.
# - Copies the generated OCaml sources (excluding `_build/` and `_gen_hx/`) into:
#     tools/hxhx-macro-host/bootstrap_out/
#
# How
# - The entrypoint allowlist is pinned to the union used by `scripts/test-hxhx-targets.sh`
#   and Gate1 runners.
#
# Notes
# - This script is expected to be run by repo maintainers as part of a controlled update.
# - Do not edit files inside `bootstrap_out/` by hand.

HAXE_BIN="${HAXE_BIN:-haxe}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL_DIR="$ROOT/tools/hxhx-macro-host"
OUT_DIR="$TOOL_DIR/out"
BOOTSTRAP_DIR="$TOOL_DIR/bootstrap_out"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Missing dune/ocamlc on PATH." >&2
  exit 1
fi

if [ ! -d "$TOOL_DIR" ]; then
  echo "Missing tool directory: $TOOL_DIR" >&2
  exit 1
fi

ENTRYPOINTS="hxhxmacros.ExternalMacros.external();hxhxmacros.BuildFieldMacros.addGeneratedField();hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn();hxhxmacros.ReturnFieldMacros.replaceGeneratedFieldReturn();hxhxmacros.FieldPrinterMacros.addArgFunctionAndVar();hxhxmacros.ExprMacroShim.hello();hxhxmacros.ArgsMacros.setArg(\"ok\");hxhxmacros.HaxelibInitMacros.init();hxhxmacros.PluginFixtureMacros.init();Macro.init()"

echo "== Regenerating macro host via stage0 (this requires Haxe + reflaxe.ocaml)"
(
  cd "$ROOT"
  HXHX_MACRO_HOST_FORCE_STAGE0=1 \
  HXHX_MACRO_HOST_EXTRA_CP="$ROOT/examples/hxhx-macros/src" \
  HXHX_MACRO_HOST_ENTRYPOINTS="$ENTRYPOINTS" \
  bash "$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" >/dev/null
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
