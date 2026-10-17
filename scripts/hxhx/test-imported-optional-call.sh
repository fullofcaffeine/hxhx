#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${HXHX_BIN:?Set HXHX_BIN to the native compiler under test}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Observe the generated program: compiler success alone can hide a dropped call.
output="$(HXHX_FORBID_STAGE0=1 "$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies \
  -cp "$ROOT/test/fixtures/stage3_imported_optional_call/src" \
  -main consumer.Main --hxhx-out "$work_dir/out")"
if ! printf '%s\n' "$output" | grep -Fxq 'imported-call:executed'; then
  printf '%s\n' 'Imported optional call produced no runtime marker.' "$output" >&2
  exit 1
fi
printf '%s\n' "$output" | grep -Fxq 'run=ok'
printf '%s\n' 'IMPORTED_OPTIONAL_CALL:PASS'
