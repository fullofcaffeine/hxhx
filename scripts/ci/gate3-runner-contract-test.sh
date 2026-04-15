#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runner="$ROOT/scripts/hxhx/run-upstream-runci-targets.sh"

grep -Fq 'if [ "\${HXHX_FORBID_STAGE0:-0}" = "1" ]; then' "$runner"
grep -Fq 'exec "${HXHX_BIN}" "\$@"' "$runner"
grep -Fq 'exec "${HXHX_BIN}" --compat "\$@"' "$runner"

strict_line="$(grep -nF 'exec "${HXHX_BIN}" "\$@"' "$runner" | head -n 1 | cut -d: -f1)"
compat_line="$(grep -nF 'exec "${HXHX_BIN}" --compat "\$@"' "$runner" | head -n 1 | cut -d: -f1)"
if [ "$strict_line" -ge "$compat_line" ]; then
  echo "strict native wrapper path must appear before compat fallback" >&2
  exit 1
fi

trap_pattern='trap '\''if [ -n "${watch_sleep_pid:-}" ]; then kill "$watch_sleep_pid" 2>/dev/null || true; fi; exit 0'\'' TERM INT'
trap_count="$(grep -Fc "$trap_pattern" "$runner")"
if [ "$trap_count" -lt 2 ]; then
  echo "Gate3 heartbeat and timeout watchers must use interruptible sleeps" >&2
  exit 1
fi

(
  watch_sleep_pid=""
  trap 'if [ -n "${watch_sleep_pid:-}" ]; then kill "$watch_sleep_pid" 2>/dev/null || true; fi; exit 0' TERM INT
  sleep 60 &
  watch_sleep_pid="$!"
  wait "$watch_sleep_pid" || exit 0
  echo "watcher sleep was not interrupted" >&2
  exit 1
) &
watcher_pid="$!"

sleep 0.1
start_epoch="$(date +%s)"
kill "$watcher_pid" 2>/dev/null || true
wait "$watcher_pid" 2>/dev/null || true
elapsed="$(( $(date +%s) - start_epoch ))"

if [ "$elapsed" -gt 2 ]; then
  echo "watcher interrupt took ${elapsed}s" >&2
  exit 1
fi

echo "gate3 runner contract OK"
