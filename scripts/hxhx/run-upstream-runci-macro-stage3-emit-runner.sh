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

# Prefer building `hxhx` from source for this rung so it always reflects the current
# Stage3 emitter lowering logic (bootstrap snapshots can lag behind when regen is slow).
export HXHX_FORCE_STAGE0=1
# Provide periodic progress so long Stage0 builds don't look "stuck".
if [ -z "${HXHX_STAGE0_HEARTBEAT:-}" ] || [ "${HXHX_STAGE0_HEARTBEAT:-0}" = "0" ]; then
  export HXHX_STAGE0_HEARTBEAT=30
  export HXHX_STAGE0_HEARTBEAT_TAIL_LINES=3
fi
HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"

# Use the repo's committed bootstrap macro host snapshot by default so this rung stays stage0-free.
if [ -z "${HXHX_MACRO_HOST_EXE:-}" ]; then
  HXHX_MACRO_HOST_EXE="$("$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1)"
  export HXHX_MACRO_HOST_EXE
fi

echo "== Gate 2 (stage3 emit runner rung): upstream tests/RunCi.hxml"
echo "UPSTREAM_DIR=$UPSTREAM_DIR"
echo "HAXE_STD_PATH=${HAXE_STD_PATH:-}"
echo "HXHX_BIN=$HXHX_BIN"
echo "HXHX_MACRO_HOST_EXE=${HXHX_MACRO_HOST_EXE:-}"

tmp_out="$(mktemp)"
set +e
(
  cd "$UPSTREAM_DIR/tests"
  rm -rf out_hxhx_runci_stage3_emit_runner
  "$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run RunCi.hxml --hxhx-out out_hxhx_runci_stage3_emit_runner 2>&1 | tee "$tmp_out"
)
code=$?
set -e
out="$(cat "$tmp_out")"
rm -f "$tmp_out"
if [ "$code" -ne 0 ]; then
  echo "Gate 2 (stage3 emit runner rung) failed with exit code $code" >&2
  exit "$code"
fi

echo "$out" | grep -q "^resolved_modules="
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^run=skipped$"

# Keep the bring-up emitter output warning-clean under strict dune setups.
if echo "$out" | grep -E -q "Warning 21 \\[nonreturning-statement\\]|Warning 26 \\[unused-var\\]"; then
  echo "Stage3 emit runner rung produced OCaml warnings (21/26). Tighten EmitterStage lowering." >&2
  exit 1
fi
