#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runner="$ROOT/scripts/hxhx/run-upstream-runci-targets.sh"
macro_runner="$ROOT/scripts/hxhx/run-upstream-runci-macro.sh"
gate3_workflow="$ROOT/.github/workflows/gate3.yml"
extended_workflow="$ROOT/.github/workflows/gate3-full1-extended.yml"
m7_workflow="$ROOT/.github/workflows/gate-m7.yml"
testing_doc="$ROOT/docs/01-getting-started/TESTING.md"

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
grep -Fq 'lua-luasec-direct-rockspec' "$runner"
grep -Fq 'cat >"$WRAP_DIR/lua"' "$runner"
grep -Fq 'kill_process_tree()' "$runner"
grep -Fq 'kill_process_tree "$target_pid" TERM' "$runner"
grep -Fq 'kill_process_tree "$target_pid" KILL' "$runner"
grep -Fq "printf '%s\\n' \"\${REQUESTED_TARGETS}\"" "$extended_workflow"
grep -Fq 'HXHX_GATE3_TARGET_TIMEOUT_SEC: "4200"' "$gate3_workflow"
grep -Fq 'HXHX_GATE3_TARGET_TIMEOUT_SEC: "4200"' "$extended_workflow"
grep -Fq 'HXHX_GATE3_TARGET_TIMEOUT_SEC: "4200"' "$m7_workflow"
grep -Fq 'HXHX_GATE3_TARGET_TIMEOUT_SEC=4200' "$testing_doc"

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

if command -v pgrep >/dev/null 2>&1; then
  kill_process_tree_contract() {
    local pid="$1"
    local signal="${2:-TERM}"
    local child=""

    if [ -z "$pid" ]; then
      return 0
    fi

    while IFS= read -r child; do
      if [ -n "$child" ]; then
        kill_process_tree_contract "$child" "$signal"
      fi
    done < <(pgrep -P "$pid" 2>/dev/null || true)

    kill "-$signal" "$pid" 2>/dev/null || true
  }

  tmp_dir="$(mktemp -d)"
  cleanup_tree_contract() {
    if [ -n "${tree_parent_pid:-}" ]; then
      kill_process_tree_contract "$tree_parent_pid" KILL
      wait "$tree_parent_pid" 2>/dev/null || true
    fi
    rm -rf "$tmp_dir"
  }
  trap cleanup_tree_contract EXIT

  child_pid_file="$tmp_dir/child.pid"
  cat >"$tmp_dir/spawn-child.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

trap 'exit 0' TERM
bash -c 'trap "exit 0" TERM; echo "$$" >"$1"; while :; do sleep 1; done' bash "$CHILD_PID_FILE" &
child="$!"
wait "$child" 2>/dev/null || true
EOF
  chmod +x "$tmp_dir/spawn-child.sh"

  CHILD_PID_FILE="$child_pid_file" "$tmp_dir/spawn-child.sh" >/dev/null 2>&1 &
  tree_parent_pid="$!"

  for _ in $(seq 1 50); do
    if [ -s "$child_pid_file" ]; then
      break
    fi
    sleep 0.1
  done

  if [ ! -s "$child_pid_file" ]; then
    echo "tree contract child did not start" >&2
    exit 1
  fi

  tree_child_pid="$(cat "$child_pid_file")"
  kill_process_tree_contract "$tree_parent_pid" TERM

  for _ in $(seq 1 50); do
    if ! kill -0 "$tree_parent_pid" 2>/dev/null && ! kill -0 "$tree_child_pid" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done

  if kill -0 "$tree_child_pid" 2>/dev/null; then
    echo "timeout process-tree kill left child process running" >&2
    exit 1
  fi

  wait "$tree_parent_pid" 2>/dev/null || true
  tree_parent_pid=""
  trap - EXIT
  rm -rf "$tmp_dir"
fi

echo "gate3 runner contract OK"
