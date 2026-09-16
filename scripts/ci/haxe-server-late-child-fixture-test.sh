#!/usr/bin/env bash
set -euo pipefail

# A child created after readiness must remain stoppable after its launcher exits.
# The second case pauses identity publication while a concurrent stop waits.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="${HXHX_TEST_SERVER_HELPER:-$ROOT/scripts/hxhx/haxe-server.sh}"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/hxhx-late-child.XXXXXX")"
export HXHX_STATE_DIR="$TEST_TMP/state"
export HXHX_HAXE_SERVER_PORT=31983
export HAXE_BIN="$TEST_TMP/fake-haxe-wrapper"
export TEST_GATE="$TEST_TMP/release-child"
export TEST_CHILD_CAPTURE="$TEST_TMP/child.pid"
export TEST_CHILD_BIN="$TEST_TMP/fake-haxe-child"
export TEST_OBSERVER_ENTERED="$TEST_TMP/observer-entered"
export TEST_OBSERVER_RELEASE="$TEST_TMP/observer-release"
export TEST_REAL_PS="$(command -v ps)"
wrapper_pid=""
child_pid=""
observer_pid=""
stop_pid=""

fail() {
	echo "[haxe-server-late-child-fixture-test] ERROR: $*" >&2
	exit 1
}

cleanup() {
	# Release the test barrier before asking the helper to acquire its state lock.
	touch "$TEST_OBSERVER_RELEASE"
	[ -z "$observer_pid" ] || wait "$observer_pid" 2>/dev/null || true
	[ -z "$stop_pid" ] || wait "$stop_pid" 2>/dev/null || true
	bash "$HELPER" stop >/dev/null 2>&1 || true
	for pid in "$wrapper_pid" "$child_pid"; do
		[ -n "$pid" ] || continue
		case "$("$TEST_REAL_PS" -o command= -p "$pid" 2>/dev/null || true)" in
			*"$TEST_TMP/"*) kill -TERM "$pid" 2>/dev/null || true ;;
		esac
	done
	rm -rf "$TEST_TMP"
}
trap cleanup EXIT

cat >"$TEST_CHILD_BIN" <<'CHILD'
#!/bin/bash
trap 'exit 0' TERM INT
while true; do sleep 0.1; done
CHILD
cat >"$HAXE_BIN" <<'WRAPPER'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "--wait" ]; then
  trap 'exit 0' TERM INT
  IFS= read -r release <"$TEST_GATE"
  "$TEST_CHILD_BIN" --wait 32983 &
  printf '%s\n' "$!" >"$TEST_CHILD_CAPTURE"
  while true; do sleep 0.1; done
fi
if [ "${1:-}" = "--connect" ]; then exit 0; fi
if [ "${1:-}" = "--version" ]; then echo 4.3.7; exit 0; fi
exit 2
WRAPPER
mkdir -p "$TEST_TMP/bin"
cat >"$TEST_TMP/bin/ps" <<'PS'
#!/bin/bash
set -euo pipefail
if [ "${TEST_PAUSE_OBSERVER:-0}" = "1" ] && [ "${1:-}" = "-o" ] \
  && [ "${2:-}" = "lstart=" ] && [ "${4:-}" = "$(cat "$TEST_CHILD_CAPTURE")" ]; then
  printf 'ready\n' >"$TEST_OBSERVER_ENTERED"
  for attempt in {1..100}; do
    if [ -e "$TEST_OBSERVER_RELEASE" ]; then exec "$TEST_REAL_PS" "$@"; fi
    sleep 0.1
  done
  exit 98
fi
exec "$TEST_REAL_PS" "$@"
PS
chmod +x "$HAXE_BIN" "$TEST_CHILD_BIN" "$TEST_TMP/bin/ps"
export PATH="$TEST_TMP/bin:$PATH"

wait_for_file() {
	for attempt in {1..50}; do
		[ ! -s "$1" ] || return 0
		sleep 0.1
	done
	fail "test barrier did not arrive: $1"
}

start_late_child() {
	rm -f "$TEST_GATE" "$TEST_CHILD_CAPTURE" "$TEST_OBSERVER_ENTERED" "$TEST_OBSERVER_RELEASE"
	mkfifo "$TEST_GATE"
	bash "$HELPER" start
	wrapper_pid="$(cat "$HXHX_STATE_DIR/haxe-server.pid")"
	printf 'release\n' >"$TEST_GATE"
	wait_for_file "$TEST_CHILD_CAPTURE"
	child_pid="$(cat "$TEST_CHILD_CAPTURE")"
}

exit_launcher() {
	kill -TERM "$wrapper_pid"
	for attempt in {1..50}; do
		kill -0 "$wrapper_pid" 2>/dev/null || return 0
		sleep 0.1
	done
	fail "launcher did not exit"
}

assert_stopped() {
	if kill -0 "$child_pid" 2>/dev/null; then
		"$TEST_REAL_PS" -o pid,ppid,state,command -p "$child_pid" >&2
		fail "observed child survived launcher exit and stop"
	fi
	for name in pid pids bin; do
		[ ! -e "$HXHX_STATE_DIR/haxe-server.$name" ] || fail "stop retained $name state"
	done
	wrapper_pid=""
	child_pid=""
}

start_late_child
bash "$HELPER" owned-pids >"$TEST_TMP/owned-pids"
grep -Fx "$child_pid" "$TEST_TMP/owned-pids" >/dev/null || fail "late child was not observed"
# A failed lock acquisition must not fall through to server cleanup.
printf '#!/bin/sh\nexit 75\n' >"$TEST_TMP/bin/flock"
chmod +x "$TEST_TMP/bin/flock"
if bash "$HELPER" stop >"$TEST_TMP/lock-failure.log" 2>&1; then
	fail "stop ignored a failed state lock"
else
	[ "$?" = 75 ] || fail "stop did not preserve the lock failure status"
fi
rm "$TEST_TMP/bin/flock"
kill -0 "$wrapper_pid" 2>/dev/null || fail "failed lock acquisition stopped the launcher"
kill -0 "$child_pid" 2>/dev/null || fail "failed lock acquisition stopped the child"
exit_launcher
bash "$HELPER" stop
assert_stopped

start_late_child
TEST_PAUSE_OBSERVER=1 bash "$HELPER" owned-pids >"$TEST_TMP/owned-pids" &
observer_pid="$!"
wait_for_file "$TEST_OBSERVER_ENTERED"
if (
	exec 9>"$HXHX_STATE_DIR/haxe-server.lock"
	if command -v flock >/dev/null 2>&1; then flock -w 0 9; else lockf -s -t 0 9; fi
); then
	fail "observer did not hold the state lock during identity publication"
fi
bash "$HELPER" stop >"$TEST_TMP/stop.log" 2>&1 &
stop_pid="$!"
exit_launcher
kill -0 "$stop_pid" 2>/dev/null || fail "stop bypassed the observer's state lock"
touch "$TEST_OBSERVER_RELEASE"
wait "$observer_pid"
observer_pid=""
wait "$stop_pid"
stop_pid=""
grep -Fx "$child_pid" "$TEST_TMP/owned-pids" >/dev/null || fail "observer omitted the child after release"
assert_stopped
echo "HAXE_SERVER_LATE_CHILD_FIXTURE:PASS"
