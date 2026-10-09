#!/usr/bin/env bash
set -euo pipefail

# Exercise the real source-build timeout with a launcher and a compiler child.
# A failed build must release its lease only after its owned workers stop. The
# sleeping control process belongs to the test, not the build, and must survive.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_TMP="$(mktemp -d)"
CONTROL_PID=""
cleanup() {
  local file pid
  for file in "$TEST_TMP"/*.pid; do
    [ -f "$file" ] || continue
    pid="$(cat "$file")"
    kill "$pid" 2>/dev/null || true
  done
  if [ -n "$CONTROL_PID" ]; then
    kill "$CONTROL_PID" 2>/dev/null || true
    wait "$CONTROL_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

active() {
  local state
  state="$(ps -o state= -p "$1" 2>/dev/null | tr -d ' ' || true)"
  [ -n "$state" ] && [[ "$state" != Z* ]]
}

cat >"$TEST_TMP/compiler" <<'COMPILER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$$" >"$TEST_PROCESS_DIR/launcher.pid"
sleep 120 &
printf '%s\n' "$!" >"$TEST_PROCESS_DIR/worker.pid"
wait
COMPILER
chmod +x "$TEST_TMP/compiler"
sleep 120 &
CONTROL_PID="$!"

set +e
CI=false HAXE_FAMILY_HEAVY_RUN_LEASE_OWNER_PID= HXHX_HEAVY_RUN_LEASE_OWNER_PID= \
TEST_PROCESS_DIR="$TEST_TMP" HAXE_BIN="$TEST_TMP/compiler" \
HXHX_FORCE_STAGE0=1 HXHX_STAGE0_OCAML_BUILD=byte HXHX_STAGE0_USE_REPO_SERVER=0 HAXE_CONNECT= \
HXHX_STAGE0_OUTPUT_DIR="$TEST_TMP/out" HXHX_STAGE0_HEARTBEAT=1 HXHX_STAGE0_FAILFAST_SECS=2 \
node "$ROOT/scripts/hxhx/with-heavy-run-lease.js" --lease-file "$TEST_TMP/lease.json" \
  --label timeout-cleanup-fixture -- bash "$ROOT/scripts/hxhx/build-hxhx.sh" >"$TEST_TMP/result.log" 2>&1
status="$?"
set -e
if [ "$status" -ne 1 ] || ! grep -q 'exceeded failfast limit' "$TEST_TMP/result.log"; then
  cat "$TEST_TMP/result.log" >&2
  echo "Expected a source-generation timeout" >&2
  exit 1
fi
grep -q 'HAXE_FAMILY_HEAVY_RUN:LEASE_RELEASED' "$TEST_TMP/result.log"
for role in launcher worker; do
  [ -s "$TEST_TMP/$role.pid" ] || { echo "Missing $role PID" >&2; exit 1; }
  if active "$(cat "$TEST_TMP/$role.pid")"; then
    echo "Build $role survived timeout and lease release" >&2
    exit 1
  fi
done
active "$CONTROL_PID" || { echo "Timeout stopped an unrelated process" >&2; exit 1; }
echo "BUILD_HXHX_TIMEOUT_CLEANUP:PASS"
