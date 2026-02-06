#!/usr/bin/env bash
set -euo pipefail

# Native Gate1 attempt.
#
# This is intentionally separate from `run-upstream-unit-macro.sh`, which runs the upstream
# suite through the *stage0 shim* path (delegating to the system `haxe` binary).
#
# Today, “native Gate1” is still a bring-up target: we route the upstream `compile-macro.hxml`
# through `hxhx --hxhx-stage3` to discover missing CLI/stdlib/typing gaps early.
#
# Long-term, this script is expected to run the upstream suite using a non-delegating `hxhx`
# (stage4 macro execution + a real typer/analyzer), per:
#   docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"
UPSTREAM_REF="${HAXE_UPSTREAM_REF:-4.3.7}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests/unit" ]; then
  echo "Skipping upstream Gate 1 (native): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
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
  echo "Skipping upstream Gate 1 (native): dune/ocamlc not found on PATH."
  exit 0
fi

# Stage3 bring-up relies on an explicit std root.
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

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh")"

if [ -z "${HXHX_MACRO_HOST_EXE:-}" ]; then
  # Gate1's `compile-macro.hxml` runs `--macro Macro.init()`, which lives in the upstream unit sources.
  # Build a macro host that:
  # - includes the upstream unit classpath, and
  # - allowlists the exact Macro.init() entrypoint for the bring-up dispatch registry.
  HXHX_MACRO_HOST_EXE="$(
    HXHX_MACRO_HOST_EXTRA_CP="$UPSTREAM_DIR/tests/unit/src" \
    HXHX_MACRO_HOST_ENTRYPOINTS="Macro.init()" \
    "$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1
  )"
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

echo "== Gate 1 (native attempt): upstream tests/unit/compile-macro.hxml (via hxhx --hxhx-stage3)"
out="$(
  cd "$UPSTREAM_DIR/tests/unit"
  # Use `--hxhx-type-only` to avoid “false positive” success from the bootstrap emitter: Stage3 does
  # not implement real Haxe typing/codegen yet, so we want this runner to prove we can at least
  # resolve + type-check (best-effort) the transitive module graph.
  HAXE_BIN="$HAXE_BIN" HAXELIB_BIN="$HAXELIB_BIN" "$HXHX_BIN" --hxhx-stage3 --hxhx-type-only compile-macro.hxml 2>&1
)"
echo "$out"

echo "$out" | grep -q "^resolved_modules="
echo "$out" | grep -q "^typed_modules="
echo "$out" | grep -q "^header_only_modules=0$"
echo "$out" | grep -q "^stage3=type_only_ok$"
