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

cleanup() {
	HXHX_STATE_DIR="$STATE_DIR" HXHX_HAXE_SERVER_PORT="$PORT" HAXE_BIN="$TMP_DIR/fake-haxe-b" \
		bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true
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
write_fake_haxe "$TMP_DIR/fake-haxe-b"
fake_a_identity="$(cd "$(dirname "$TMP_DIR/fake-haxe-a")" && pwd -P)/fake-haxe-a"
fake_b_identity="$(cd "$(dirname "$TMP_DIR/fake-haxe-b")" && pwd -P)/fake-haxe-b"

run_helper() {
	local haxe_bin="$1"
	shift
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

status="$(run_helper "$TMP_DIR/fake-haxe-b" status)"
case "$status" in
	*"pid=$replacement_pid"*"haxe_bin=$fake_b_identity"*)
		;;
	*)
		fail "status did not identify the replacement server: $status"
		;;
esac

run_helper "$TMP_DIR/fake-haxe-b" stop >/dev/null
[ ! -e "$STATE_DIR/haxe-server.pid" ] || fail "stop left the PID file behind"
[ ! -e "$STATE_DIR/haxe-server.bin" ] || fail "stop left the executable identity behind"

echo "HAXE_SERVER_IDENTITY_FIXTURE:PASS"
