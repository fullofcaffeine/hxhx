#!/usr/bin/env bash
set -euo pipefail

# Native Gate1 attempt.
#
# Today, "native Gate1" is still a bring-up target: we route the upstream `compile-macro.hxml`
# through `hxhx --hxhx-stage3` to discover missing CLI/stdlib/typing gaps early.
#
# Long-term, this script is expected to run the upstream suite using a non-delegating `hxhx`
# (stage4 macro execution + a real typer/analyzer), per:
#   docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md

HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"
UPSTREAM_REF="${HAXE_UPSTREAM_REF:-4.3.7}"
ALLOW_STAGE0="${HXHX_ALLOW_STAGE0:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests/unit" ]; then
  echo "Skipping upstream Gate 1 (native): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v "$HAXELIB_BIN" >/dev/null 2>&1; then
  echo "Missing haxelib on PATH (expected '$HAXELIB_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream Gate 1 (native): dune/ocamlc not found on PATH."
  exit 0
fi

# Guardrail: this runner is intended to be stage0-free with respect to the Haxe compiler binary.
#
# If we accidentally invoke `haxe` (directly or indirectly), we want it to fail loudly.
if [ -z "$ALLOW_STAGE0" ]; then
  export HAXE_BIN="__hxhx_stage0_disabled__"
fi

# Make the runner deterministic and stage0-free even if the user's shell environment has
# stage0-related knobs set.
unset HXHX_FORCE_STAGE0 || true
unset HXHX_MACRO_HOST_FORCE_STAGE0 || true
unset HXHX_MACRO_HOST_ENTRYPOINTS || true
unset HXHX_MACRO_HOST_EXTRA_CP || true

# Stage3 bring-up relies on an explicit std root.
#
# Prefer upstream's `std/` when available, because `haxe` can be a shim (e.g. lix)
# that doesn't sit next to a `std` folder on disk.
if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"

if [ -z "${HXHX_MACRO_HOST_EXE:-}" ]; then
  # Gate1's `compile-macro.hxml` runs `--macro Macro.init()`.
  #
  # For CI-friendliness and to keep this runner stage0-free with respect to macro-host
  # selection, we use the repo's committed bootstrap macro host snapshot when available
  # (see `tools/hxhx-macro-host/bootstrap_out`).
  #
  # NOTE: This does *not* execute upstream's real `tests/unit/src/Macro.hx` yet. The
  # bring-up goal here is to exercise the macro ABI boundary (spawn + handshake +
  # hook registration), not to validate upstream macro semantics.
  HXHX_MACRO_HOST_EXE="$("$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1)"
  export HXHX_MACRO_HOST_EXE
fi

# Ensure utest exists (upstream pins it; match the pin so fixture content stays stable).
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

echo "== Gate 1 (native attempt): upstream tests/unit/compile-macro.hxml (via hxhx --hxhx-stage3 emit+build+run)"
#
# NOTE
# - This is still bring-up, not a claim of full upstream Gate1 correctness.
# - The Stage3 emitter is intentionally non-semantic in places; the goal here is to ensure we can
#   compile and execute upstream-shaped workloads end-to-end without invoking stage0 `haxe`.
# - Darwin SIGSEGV skip mode has been removed; the stage3 rung should now pass directly.
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-upstream-unit-macro-stage3-emit.sh"
