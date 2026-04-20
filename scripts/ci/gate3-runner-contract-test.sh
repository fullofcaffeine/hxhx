#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runner="$ROOT/scripts/hxhx/run-upstream-runci-targets.sh"
macro_runner="$ROOT/scripts/hxhx/run-upstream-runci-macro.sh"
extended_workflow="$ROOT/.github/workflows/gate3-full1-extended.yml"

grep -Fq 'if [ "\${HXHX_FORBID_STAGE0:-0}" = "1" ]; then' "$runner"
grep -Fq 'exec "${HXHX_BIN}" "\$@"' "$runner"
grep -Fq 'exec "${HXHX_BIN}" --compat "\$@"' "$runner"
grep -Fq 'resolve_system_neko_bin()' "$runner"
grep -Fq 'resolve_system_nekotools_bin()' "$runner"
grep -Fq 'system_neko="$(resolve_system_neko_bin || true)"' "$runner"
grep -Fq 'STAGE0_NEKO="$system_neko"' "$runner"
grep -Fq 'is_lix_neko_shim()' "$runner"
grep -Fq 'NEKO_WRAPPER_EXPORT_NEKOPATH=0' "$runner"
grep -Fq 'if [ "${NEKO_WRAPPER_EXPORT_NEKOPATH}" = "1" ] && [ -n "${NEKOPATH_DIR}" ]; then' "$runner"
grep -Fq 'unset NEKOPATH' "$runner"
grep -Fq 'unset LD_LIBRARY_PATH' "$runner"
grep -Fq 'resolve_lua_bin()' "$runner"
grep -Fq 'command -v lua5.4' "$runner"
grep -Fq 'need_cmd luarocks "Lua target dependencies"' "$runner"
grep -Fq 'cat >"$WRAP_DIR/lua"' "$runner"
grep -Fq "printf '%s\\n' \"\${REQUESTED_TARGETS}\"" "$extended_workflow"

target_pinned_line="$(grep -nF 'probes+=("$HOME/haxe/versions/$UPSTREAM_REF/haxelib")' "$runner" | head -n 1 | cut -d: -f1)"
target_requested_line="$(grep -nF 'if [ -n "$requested" ]; then' "$runner" | head -n 1 | cut -d: -f1)"
if [ "$target_pinned_line" -ge "$target_requested_line" ]; then
  echo "Gate3 haxelib resolver must prefer pinned native Haxe toolchain before PATH/requested wrappers" >&2
  exit 1
fi

grep -Fq 'resolve_runnable_haxelib()' "$macro_runner"
macro_pinned_line="$(grep -nF 'probes+=("$HOME/haxe/versions/$UPSTREAM_REF/haxelib")' "$macro_runner" | head -n 1 | cut -d: -f1)"
macro_requested_line="$(grep -nF 'if [ -n "$requested" ]; then' "$macro_runner" | head -n 1 | cut -d: -f1)"
if [ "$macro_pinned_line" -ge "$macro_requested_line" ]; then
  echo "Gate2 haxelib resolver must prefer pinned native Haxe toolchain before PATH/requested wrappers" >&2
  exit 1
fi

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
