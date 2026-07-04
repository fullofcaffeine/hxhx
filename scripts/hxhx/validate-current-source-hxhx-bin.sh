#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${HXHX_CURRENT_SOURCE_ROOT:-$SCRIPT_ROOT}"
requested_bin="${1:-${HXHX_BIN:-}}"
meta_path="${HXHX_CURRENT_SOURCE_META:-$ROOT/packages/hxhx/out/hxhx-current-source.env}"
allow_stale="${HXHX_CURRENT_SOURCE_ALLOW_STALE:-0}"

fail() {
  echo "validate-current-source-hxhx-bin: $*" >&2
  exit 1
}

tracked_status() {
  git -C "$ROOT" status --porcelain --untracked-files=no
}

tracked_tree() {
  git -C "$ROOT" diff --no-ext-diff --binary HEAD -- .
}

status_sha256() {
  shasum -a 256 | awk '{print $1}'
}

[ -n "$requested_bin" ] || fail "missing HXHX_BIN/path argument"
case "$requested_bin" in
  /*) : ;;
  */*) requested_bin="$ROOT/$requested_bin" ;;
  *) fail "HXHX_BIN must be an explicit path for current-source provenance: $requested_bin" ;;
esac

[ -f "$requested_bin" ] || fail "HXHX_BIN does not exist: $requested_bin"
if [ ! -x "$requested_bin" ] && [[ "$requested_bin" != *.bc ]]; then
  fail "HXHX_BIN is neither executable nor OCaml bytecode (*.bc): $requested_bin"
fi
[ -f "$meta_path" ] || fail "missing provenance metadata: $meta_path; run scripts/hxhx/build-current-source-hxhx.sh"

# shellcheck disable=SC1090
. "$meta_path"

[ "${HXHX_BIN_PROVENANCE:-}" = "current-source-stage0" ] || fail "unexpected HXHX_BIN_PROVENANCE=${HXHX_BIN_PROVENANCE:-missing}"
[ "${HXHX_BIN:-}" = "$requested_bin" ] || fail "metadata HXHX_BIN ($HXHX_BIN) does not match requested path ($requested_bin)"

current_head="$(git -C "$ROOT" rev-parse HEAD)"
current_status="$(tracked_status)"
current_status_sha256="$(printf '%s' "$current_status" | status_sha256)"
current_tree_sha256="$(tracked_tree | status_sha256)"

stale_reason=""
if [ "${HXHX_BIN_SOURCE_HEAD:-}" != "$current_head" ]; then
  stale_reason="git head changed: built=${HXHX_BIN_SOURCE_HEAD:-missing} current=$current_head"
elif [ -z "${HXHX_BIN_SOURCE_TREE_SHA256:-}" ]; then
  stale_reason="missing tracked worktree content hash in provenance metadata"
elif [ "${HXHX_BIN_SOURCE_TREE_SHA256:-}" != "$current_tree_sha256" ]; then
  stale_reason="tracked worktree content changed since build"
elif [ "${HXHX_BIN_SOURCE_STATUS_SHA256:-}" != "$current_status_sha256" ]; then
  stale_reason="tracked worktree status changed since build"
fi

if [ -n "$stale_reason" ] && [ "$allow_stale" != "1" ]; then
  fail "$stale_reason; rebuild with scripts/hxhx/build-current-source-hxhx.sh or set HXHX_CURRENT_SOURCE_ALLOW_STALE=1 for diagnosis-only reuse"
fi

if [ -n "$stale_reason" ]; then
  echo "validate-current-source-hxhx-bin: warning: $stale_reason" >&2
fi

echo "$requested_bin"
