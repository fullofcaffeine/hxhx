#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FETCH_SCRIPT="$ROOT/scripts/vendor/fetch-reflaxe-elixir-upstream.sh"

if [ ! -x "$FETCH_SCRIPT" ]; then
  echo "reflaxe-elixir fetch pin check: missing fetch script: $FETCH_SCRIPT" >&2
  exit 1
fi

tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

set +e
output="$(
  REFLAXE_ELIXIR_REF=main \
    REFLAXE_ELIXIR_DIR="$tmp_root/reflaxe-elixir" \
    bash "$FETCH_SCRIPT" 2>&1
)"
status="$?"
set -e

printf '%s\n' "$output"
if [ "$status" -eq 0 ]; then
  echo "reflaxe-elixir fetch pin check: unpinned branch ref unexpectedly succeeded" >&2
  exit 1
fi
if [ -e "$tmp_root/reflaxe-elixir" ]; then
  echo "reflaxe-elixir fetch pin check: unpinned ref created checkout before failing" >&2
  exit 1
fi
printf '%s\n' "$output" | grep -q 'must be a pinned 40-character commit SHA'

echo "REFLAXE_ELIXIR_UNPINNED_FAIL_FAST:PASS"
