#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
META_PATH="${HXHX_CURRENT_SOURCE_META:-$ROOT/packages/hxhx/out/hxhx-current-source.env}"
VALIDATE="$ROOT/scripts/hxhx/validate-current-source-hxhx-bin.sh"
BUILD="$ROOT/scripts/hxhx/build-current-source-hxhx.sh"

# Fast local entrypoint for tools that need an hxhx binary compiled from the
# current checkout.
#
# Use this when a diagnostic can reuse the previous current-source build. It
# checks the provenance metadata written by build-current-source-hxhx.sh and only
# rebuilds when the tracked git HEAD/status changed or the artifact is missing.
# Use build-current-source-hxhx.sh directly when you intentionally want a fresh
# rebuild regardless of cache state.

if [ -n "${HXHX_BIN:-}" ]; then
  exec "$VALIDATE" "$HXHX_BIN"
fi

if [ -f "$META_PATH" ]; then
  # shellcheck disable=SC1090
  . "$META_PATH"
  if [ -n "${HXHX_BIN:-}" ] && "$VALIDATE" "$HXHX_BIN"; then
    exit 0
  fi
  echo "== Existing current-source hxhx is missing or stale; rebuilding." >&2
else
  echo "== No current-source hxhx metadata found; building." >&2
fi

exec "$BUILD"
