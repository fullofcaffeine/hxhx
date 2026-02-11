#!/usr/bin/env bash
set -euo pipefail

# Display smoke rung (Stage3 no-emit, non-delegating).
#
# Goal
# - Exercise `--display <file@mode>` argument handling through `hxhx --hxhx-stage3 --hxhx-no-emit`
#   without relying on the upstream `--wait` display server protocol.
#
# Why this exists
# - Gate2's direct runner currently compiles `tests/display/build.hxml` but does not execute the
#   display server fixture process end-to-end under Stage3 no-emit.
# - This script provides a reproducible, dedicated display compatibility check while we continue
#   implementing full server parity.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"

if [ ! -d "$UPSTREAM_DIR/tests/display" ]; then
  echo "Skipping upstream display smoke (stage3 no-emit): missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream display smoke (stage3 no-emit): dune/ocamlc not found on PATH."
  exit 0
fi

if [ -z "${HAXE_STD_PATH:-}" ] && [ -d "$UPSTREAM_DIR/std" ]; then
  export HAXE_STD_PATH="$UPSTREAM_DIR/std"
fi

HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"

DISPLAY_FILE="$UPSTREAM_DIR/tests/display/src-shared/Marker.hx"
if [ ! -f "$DISPLAY_FILE" ]; then
  echo "Missing upstream display fixture file: $DISPLAY_FILE" >&2
  exit 1
fi

echo "== Upstream display smoke (stage3 no-emit): $DISPLAY_FILE"
out="$(
  "$HXHX_BIN" \
    --hxhx-stage3 --hxhx-no-emit \
    --hxhx-out "$UPSTREAM_DIR/tests/display/out_hxhx_display_stage3_no_emit" \
    --connect 6000 \
    --display "$DISPLAY_FILE@0@diagnostics" \
    -cp "$UPSTREAM_DIR/tests/display/src" \
    -cp "$UPSTREAM_DIR/tests/display/src-shared" \
    --no-output 2>&1
)"
echo "$out"

echo "$out" | grep -q "^stage3=no_emit_ok$"
echo "$out" | grep -qv "import_missing 6000"

