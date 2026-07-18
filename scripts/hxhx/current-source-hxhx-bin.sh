#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
META_PATH="${HXHX_CURRENT_SOURCE_META:-$ROOT/packages/hxhx/out/hxhx-current-source.env}"
VALIDATE="$ROOT/scripts/hxhx/validate-current-source-hxhx-bin.sh"
VALIDATE_DEVELOPER="$ROOT/scripts/hxhx/validate-developer-current-source-hxhx-bin.sh"
BUILD="$ROOT/scripts/hxhx/build-current-source-hxhx.sh"

validate_strict() {
  local bin="$1"
  if [ "${HXHX_CURRENT_SOURCE_ALLOW_STALE:-0}" = "1" ]; then
    "$VALIDATE" "$bin"
  else
    "$VALIDATE" "$bin" 2>/dev/null
  fi
}

# Fast local entrypoint for tools that need an hxhx binary compiled from the
# current checkout.
#
# Use this when a diagnostic can reuse the previous current-source build. It
# first accepts exact-commit provenance. When only non-compiler files changed,
# it may then reuse the artifact through the developer-only complete-input
# fingerprint. Release and parity runners call the strict validator directly
# and cannot use that shortcut.
# Use build-current-source-hxhx.sh directly when you intentionally want a fresh
# rebuild regardless of cache state.

if [ -n "${HXHX_BIN:-}" ]; then
  if validate_strict "$HXHX_BIN"; then
    exit 0
  fi
  exec "$VALIDATE_DEVELOPER" "$HXHX_BIN"
fi

if [ -f "$META_PATH" ]; then
  # shellcheck disable=SC1090
  . "$META_PATH"
  if [ -n "${HXHX_BIN:-}" ]; then
    if validate_strict "$HXHX_BIN"; then
      exit 0
    fi
    if "$VALIDATE_DEVELOPER" "$HXHX_BIN"; then
      exit 0
    fi
  fi
  echo "== Existing current-source hxhx is missing or stale; rebuilding." >&2
else
  echo "== No current-source hxhx metadata found; building." >&2
fi

exec "$BUILD"
