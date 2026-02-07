#!/usr/bin/env bash
set -euo pipefail

# Gate 2 diagnostic rung: Stage3 emit+build the upstream RunCi runner.
#
# Goal
# - Ensure `hxhx --hxhx-stage3 --hxhx-emit-full-bodies` can compile the upstream
#   `tests/RunCi.hxml` into a native OCaml executable without stage0 `haxe`.
#
# Why
# - Gate2 acceptance ultimately requires *running* the runci Macro target under a non-delegating
#   `hxhx`, but the first concrete milestone is being able to compile the upstream harness itself.
# - This rung intentionally uses `--hxhx-no-run` to avoid accidentally launching long-running
#   server-style behavior during bring-up.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests/runci" ] || [ ! -f "$UPSTREAM_DIR/tests/RunCi.hxml" ]; then
  echo "Skipping upstream Gate 2 (stage3 emit runner): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream Gate 2 (stage3 emit runner): dune/ocamlc not found on PATH."
  exit 0
fi

# Prefer upstream's `std/` for deterministic resolution (works even when `haxe` is a shim like lix).
if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh")"

# Use the repo's committed bootstrap macro host snapshot by default so this rung stays stage0-free.
if [ -z "${HXHX_MACRO_HOST_EXE:-}" ]; then
  HXHX_MACRO_HOST_EXE="$("$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1)"
  export HXHX_MACRO_HOST_EXE
fi

echo "== Gate 2 (stage3 emit runner rung): upstream tests/RunCi.hxml"
out="$(
  cd "$UPSTREAM_DIR/tests"
  rm -rf out_hxhx_runci_stage3_emit_runner
  "$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run RunCi.hxml --hxhx-out out_hxhx_runci_stage3_emit_runner 2>&1
)"
echo "$out"

echo "$out" | grep -q "^resolved_modules="
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^run=skipped$"

# Keep the bring-up emitter output warning-clean under strict dune setups.
if echo "$out" | grep -E -q "Warning 21 \\[nonreturning-statement\\]|Warning 26 \\[unused-var\\]"; then
  echo "Stage3 emit runner rung produced OCaml warnings (21/26). Tighten EmitterStage lowering." >&2
  exit 1
fi

