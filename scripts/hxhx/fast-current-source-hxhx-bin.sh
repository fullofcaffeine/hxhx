#!/usr/bin/env bash
set -euo pipefail

# Select or rebuild the isolated no-prepass developer compiler. Exact proof
# lanes deliberately use current-source-hxhx-bin.sh and the full-profile
# validator instead.

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${HXHX_CURRENT_SOURCE_ROOT:-$SCRIPT_ROOT}"
FAST_OUT_DIR="${HXHX_FAST_CURRENT_SOURCE_OUT_DIR:-$ROOT/packages/hxhx/out_tmp_current_source_fast}"
case "$FAST_OUT_DIR" in
  /*) : ;;
  *) FAST_OUT_DIR="$ROOT/$FAST_OUT_DIR" ;;
esac
META_PATH="${HXHX_FAST_CURRENT_SOURCE_META:-$FAST_OUT_DIR/hxhx-current-source-fast.env}"
VALIDATE="$SCRIPT_ROOT/scripts/hxhx/validate-fast-current-source-hxhx-bin.sh"
BUILD="$SCRIPT_ROOT/scripts/hxhx/build-fast-current-source-hxhx.sh"

if [ -n "${HXHX_BIN:-}" ]; then
  exec "$VALIDATE" "$HXHX_BIN"
fi

if [ -f "$META_PATH" ]; then
  # shellcheck disable=SC1090
  . "$META_PATH"
  if [ -n "${HXHX_BIN:-}" ] && "$VALIDATE" "$HXHX_BIN"; then
    exit 0
  fi
  echo "== Existing fast current-source hxhx is missing or stale; rebuilding." >&2
else
  echo "== No fast current-source hxhx metadata found; building." >&2
fi

exec "$BUILD"
