#!/usr/bin/env bash
set -euo pipefail

# Validate only the isolated no-prepass developer artifact. This wrapper never
# calls the exact-commit validator and therefore cannot turn fast-loop evidence
# into strict parity or release evidence.

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${HXHX_CURRENT_SOURCE_ROOT:-$SCRIPT_ROOT}"
FAST_OUT_DIR="${HXHX_FAST_CURRENT_SOURCE_OUT_DIR:-$ROOT/packages/hxhx/out_tmp_current_source_fast}"
case "$FAST_OUT_DIR" in
  /*) : ;;
  *) FAST_OUT_DIR="$ROOT/$FAST_OUT_DIR" ;;
esac

export HXHX_CURRENT_SOURCE_META="${HXHX_FAST_CURRENT_SOURCE_META:-$FAST_OUT_DIR/hxhx-current-source-fast.env}"
export HXHX_CURRENT_SOURCE_EXPECTED_PROFILE=no-prepass-dev
export HXHX_STAGE0_DISABLE_PREPASSES=1

exec bash "$SCRIPT_ROOT/scripts/hxhx/validate-developer-current-source-hxhx-bin.sh" "$@"
