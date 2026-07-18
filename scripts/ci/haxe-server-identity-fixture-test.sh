#!/usr/bin/env bash
set -euo pipefail

# Proves that the repo-owned server is reused for the same Haxe executable and
# replaced when the requested executable changes. The fake compilers never
# open a network port; they only model the helper's process lifecycle.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hxhx-haxe-server-identity.XXXXXX")"
STATE_DIR="$TMP_DIR/state"
PORT=31873
CHILD_PID_CAPTURE="$TMP_DIR/wrapper-child.pid"

cleanup() {
	HXHX_STATE_DIR="$STATE_DIR" HXHX_HAXE_SERVER_PORT="$PORT" HAXE_BIN="$TMP_DIR/fake-haxe-b" \
		bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true
	if [ -s "$CHILD_PID_CAPTURE" ]; then
		kill "$(cat "$CHILD_PID_CAPTURE")" >/dev/null 2>&1 || true
	fi
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

write_fake_haxe() {
	local target="$1"
	cat >"$target" <<'FAKE_HAXE'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--wait" ]; then
	trap 'exit 0' TERM INT
	while true; do
		sleep 1
	done
fi
if [ "${1:-}" = "--connect" ]; then
	if [ "${FAKE_HAXE_CONNECT_FAIL:-0}" = "1" ]; then
		exit 1
	fi
	exit 0
fi
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-version" ]; then
	echo "4.3.7"
	exit 0
fi
echo "unexpected fake Haxe arguments: $*" >&2
exit 1
FAKE_HAXE
	chmod +x "$target"
}

fail() {
	echo "[haxe-server-identity-fixture-test] ERROR: $*" >&2
	exit 1
}

write_fake_haxe "$TMP_DIR/fake-haxe-a"
cat >"$TMP_DIR/fake-haxe-child" <<'FAKE_HAXE_CHILD'
#!/usr/bin/env bash
set -euo pipefail
trap 'exit 0' TERM INT
while true; do
	sleep 1
done
FAKE_HAXE_CHILD
chmod +x "$TMP_DIR/fake-haxe-child"

cat >"$TMP_DIR/fake-haxe-b" <<'FAKE_HAXE_WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--wait" ]; then
	"${FAKE_HAXE_CHILD:?}" --wait "${FAKE_HAXE_CHILD_PORT:?}" &
	child_pid="$!"
	printf '%s\n' "$child_pid" >"${FAKE_HAXE_CHILD_PID_CAPTURE:?}"
	# Deliberately model a launcher that exits without forwarding TERM. The
	# repository helper must still own and stop the real server child.
	trap 'exit 0' TERM INT
	while kill -0 "$child_pid" >/dev/null 2>&1; do
		sleep 1
	done
	exit 0
fi
if [ "${1:-}" = "--connect" ]; then
	if [ "${FAKE_HAXE_CONNECT_FAIL:-0}" = "1" ]; then
		exit 1
	fi
	exit 0
fi
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-version" ]; then
	echo "4.3.7"
	exit 0
fi
echo "unexpected fake Haxe arguments: $*" >&2
exit 1
FAKE_HAXE_WRAPPER
chmod +x "$TMP_DIR/fake-haxe-b"
fake_a_identity="$(cd "$(dirname "$TMP_DIR/fake-haxe-a")" && pwd -P)/fake-haxe-a"
fake_b_identity="$(cd "$(dirname "$TMP_DIR/fake-haxe-b")" && pwd -P)/fake-haxe-b"

run_helper() {
	local haxe_bin="$1"
	shift
	FAKE_HAXE_CHILD="$TMP_DIR/fake-haxe-child" \
	FAKE_HAXE_CHILD_PID_CAPTURE="$CHILD_PID_CAPTURE" \
	FAKE_HAXE_CHILD_PORT="$((PORT + 1000))" \
	HXHX_STATE_DIR="$STATE_DIR" HXHX_HAXE_SERVER_PORT="$PORT" HAXE_BIN="$haxe_bin" \
		bash "$SERVER_HELPER" "$@"
}

run_helper "$TMP_DIR/fake-haxe-a" start >/dev/null
first_pid="$(cat "$STATE_DIR/haxe-server.pid")"
first_identity="$(cat "$STATE_DIR/haxe-server.bin")"
[ "$first_identity" = "$fake_a_identity" ] || fail "first server identity was not recorded"

run_helper "$TMP_DIR/fake-haxe-a" start >/dev/null
reused_pid="$(cat "$STATE_DIR/haxe-server.pid")"
[ "$reused_pid" = "$first_pid" ] || fail "same executable did not reuse the server"

run_helper "$TMP_DIR/fake-haxe-b" start >/dev/null
replacement_pid="$(cat "$STATE_DIR/haxe-server.pid")"
replacement_identity="$(cat "$STATE_DIR/haxe-server.bin")"
[ "$replacement_pid" != "$first_pid" ] || fail "different executable did not replace the server"
[ "$replacement_identity" = "$fake_b_identity" ] || fail "replacement identity was not recorded"
if kill -0 "$first_pid" >/dev/null 2>&1; then
	fail "old server process remained alive after replacement"
fi

replacement_child_pid="$(cat "$CHILD_PID_CAPTURE")"
run_helper "$TMP_DIR/fake-haxe-b" start >/dev/null
reused_wrapper_pid="$(cat "$STATE_DIR/haxe-server.pid")"
reused_child_pid="$(cat "$CHILD_PID_CAPTURE")"
[ "$reused_wrapper_pid" = "$replacement_pid" ] || fail "same wrapper executable did not reuse its launcher"
[ "$reused_child_pid" = "$replacement_child_pid" ] || fail "same wrapper executable spawned a second server child"

status="$(run_helper "$TMP_DIR/fake-haxe-b" status)"
case "$status" in
	*"pid=$replacement_pid"*"haxe_bin=$fake_b_identity"*)
		;;
	*)
		fail "status did not identify the replacement server: $status"
		;;
esac

# Model a launcher crash after readiness. The child uses a different internal
# wait port, just like the real Lix wrapper, so cleanup must trust the recorded
# process identity rather than rediscovering it from the public port.
kill -TERM "$replacement_pid"
for _attempt in 1 2 3 4 5 6 7 8 9 10; do
	if ! kill -0 "$replacement_pid" >/dev/null 2>&1; then
		break
	fi
	sleep 0.1
done
if kill -0 "$replacement_pid" >/dev/null 2>&1; then
	fail "wrapper did not exit during launcher-crash fixture"
fi
kill -0 "$replacement_child_pid" >/dev/null 2>&1 \
	|| fail "launcher crash unexpectedly stopped its native child"

run_helper "$TMP_DIR/fake-haxe-b" stop >/dev/null
[ ! -e "$STATE_DIR/haxe-server.pid" ] || fail "stop left the PID file behind"
[ ! -e "$STATE_DIR/haxe-server.pids" ] || fail "stop left the process-tree file behind"
[ ! -e "$STATE_DIR/haxe-server.bin" ] || fail "stop left the executable identity behind"
wrapper_child_pid="$(cat "$CHILD_PID_CAPTURE")"
if kill -0 "$wrapper_child_pid" >/dev/null 2>&1; then
	fail "stop left the wrapper's real Haxe server child alive"
fi

# Interrupt the helper while it is waiting for readiness. Its EXIT path must
# stop both the launcher and its native child instead of leaving a server from
# a canceled development command.
rm -f "$CHILD_PID_CAPTURE"
FAKE_HAXE_CHILD="$TMP_DIR/fake-haxe-child" \
FAKE_HAXE_CHILD_PID_CAPTURE="$CHILD_PID_CAPTURE" \
FAKE_HAXE_CHILD_PORT="$((PORT + 1000))" \
FAKE_HAXE_CONNECT_FAIL=1 \
HXHX_STATE_DIR="$STATE_DIR" HXHX_HAXE_SERVER_PORT="$PORT" HAXE_BIN="$TMP_DIR/fake-haxe-b" \
	bash "$SERVER_HELPER" start >"$TMP_DIR/interrupted-start.log" 2>&1 &
helper_pid="$!"
for _attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	if [ -s "$CHILD_PID_CAPTURE" ]; then
		break
	fi
	sleep 0.05
done
[ -s "$CHILD_PID_CAPTURE" ] || fail "interrupted-start fixture never spawned its server child"
interrupted_child_pid="$(cat "$CHILD_PID_CAPTURE")"
kill -TERM "$helper_pid"
set +e
wait "$helper_pid"
helper_code="$?"
set -e
[ "$helper_code" = "143" ] || fail "interrupted start exited $helper_code instead of 143"
if kill -0 "$interrupted_child_pid" >/dev/null 2>&1; then
	fail "interrupted start left the wrapper's real Haxe server child alive"
fi
[ ! -e "$STATE_DIR/haxe-server.pid" ] || fail "interrupted start left server PID state behind"
[ ! -e "$STATE_DIR/haxe-server.pids" ] || fail "interrupted start left process-tree state behind"
[ ! -e "$STATE_DIR/haxe-server.bin" ] || fail "interrupted start left server identity state behind"

echo "HAXE_SERVER_IDENTITY_FIXTURE:PASS"
