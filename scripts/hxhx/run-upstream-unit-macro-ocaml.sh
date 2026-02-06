#!/usr/bin/env bash
set -euo pipefail

# Gate 1 (OCaml --interp emulation).
#
# Why
# - Upstream runs `tests/unit/compile-macro.hxml` with `--interp`.
# - For a native target like OCaml, we emulate that workflow as:
#     compile → dune build (native) → run produced binary
#
# What this does today
# - Uses stage0 `haxe` (through the `hxhx` shim) to compile the unit macro suite to OCaml.
# - Builds a native executable via dune (reflaxe.ocaml’s `ocaml_build=native`).
# - Runs the produced binary and returns its exit code.
#
# Non-goal
# - This does not remove the stage0 dependency yet. The non-delegating swap is tracked separately.

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"
UPSTREAM_REF="${HAXE_UPSTREAM_REF:-4.3.7}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests/unit" ]; then
  echo "Skipping upstream Gate 1 (ocaml interp emulation): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
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

# Stage0 OCaml target runs inside the stage0 `haxe` process.
#
# When using lix-managed wrappers (e.g. `~/.nvm/.../bin/haxe`), the wrapper itself does not live
# next to `std/`, so “infer std path by dirname(haxeBin)” is brittle.
#
# Instead, prefer setting HAXE_STD_PATH from the lix-managed install location if it exists.
# Note: we intentionally keep using the wrapper `haxe`/`haxelib` binaries (not the upstream OCaml ones),
# because on macOS the upstream `haxelib` binary can require a Neko dylib at runtime.
if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$HOME/haxe/versions/$UPSTREAM_REF/std" ]; then
  export HAXE_STD_PATH="$HOME/haxe/versions/$UPSTREAM_REF/std"
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream Gate 1 (ocaml interp emulation): dune/ocamlc not found on PATH."
  exit 0
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

echo "== Gate 1 (ocaml --interp emulation): upstream tests/unit/compile-macro.hxml"
(
  cd "$UPSTREAM_DIR/tests/unit"
  # Use a deterministic output dir inside the upstream test folder to avoid interfering with other runs.
  #
  # IMPORTANT:
  # - Do NOT rely on `--target ocaml` here: in dev (non-dist) builds the preset would inject `-lib reflaxe.ocaml`,
  #   which only resolves when executed from this repo root (scoped haxe_libraries).
  # - Instead, inject reflaxe.ocaml directly via `-cp` + init macros, so this runner works from inside upstream.
  HAXE_BIN="$HAXE_BIN" HAXELIB_BIN="$HAXELIB_BIN" "$HXHX_BIN" \
    --hxhx-ocaml-interp \
    --hxhx-ocaml-out out_hxhx_unit_macro_ocaml \
    -- \
    -cp "$ROOT/src" \
    -cp "$ROOT/std" \
    -cp "$ROOT/test/upstream_shims" \
    -lib reflaxe \
    --macro 'nullSafety("reflaxe")' \
    --macro 'reflaxe.ReflectCompiler.Start()' \
    --macro 'reflaxe.ocaml.CompilerInit.Start()' \
    -D reflaxe-target=ocaml \
    -D reflaxe-target-code-injection=ocaml \
    -D retain-untyped-meta \
    compile-macro.hxml
)
