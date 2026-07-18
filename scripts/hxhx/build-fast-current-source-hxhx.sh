#!/usr/bin/env bash
set -euo pipefail

# Build the developer-only current-source compiler without Reflaxe expression
# preprocessors. Its output and receipt are intentionally isolated from the
# full compiler used by strict parity and release workflows.

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${HXHX_CURRENT_SOURCE_ROOT:-$SCRIPT_ROOT}"
FAST_OUT_DIR="${HXHX_FAST_CURRENT_SOURCE_OUT_DIR:-$ROOT/packages/hxhx/out_tmp_current_source_fast}"
case "$FAST_OUT_DIR" in
  /*) : ;;
  *) FAST_OUT_DIR="$ROOT/$FAST_OUT_DIR" ;;
esac

export HXHX_CURRENT_SOURCE_BUILD_PROFILE=no-prepass-dev
export HXHX_CURRENT_SOURCE_META="${HXHX_FAST_CURRENT_SOURCE_META:-$FAST_OUT_DIR/hxhx-current-source-fast.env}"
export HXHX_CURRENT_SOURCE_INPUT_REPORT="${HXHX_FAST_CURRENT_SOURCE_INPUT_REPORT:-$FAST_OUT_DIR/hxhx-current-source-fast.inputs.json}"
export HXHX_STAGE0_OUTPUT_DIR="$FAST_OUT_DIR"
export HXHX_STAGE0_DISABLE_PREPASSES=1

exec bash "$SCRIPT_ROOT/scripts/hxhx/build-current-source-hxhx.sh"
