#!/usr/bin/env bash
set -euo pipefail

# Proves that the build monitor follows the verified repository-server process
# tree. The foreground --connect client waits quietly while a native child of a
# wrapper server uses CPU, which must not be mistaken for a stalled handoff.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_TMP="$(mktemp -d)"
STATE_DIR="$TEST_TMP/state"
TRACE_FILE="$TEST_TMP/fake-haxe.trace"
WORKER_PID_FILE="$TEST_TMP/worker.pid"
FAKE_HAXE="$TEST_TMP/fake-haxe.sh"
FAKE_WORKER="$TEST_TMP/fake-haxe-worker.sh"
OUTPUT_FILE="$TEST_TMP/build.output"
PORT=31907

cleanup() {
	HXHX_STATE_DIR="$STATE_DIR" HXHX_HAXE_SERVER_PORT="$PORT" HAXE_BIN="$FAKE_HAXE" \
		bash "$ROOT/scripts/hxhx/haxe-server.sh" stop >/dev/null 2>&1 || true
	if [ -s "$WORKER_PID_FILE" ]; then
		kill "$(cat "$WORKER_PID_FILE")" >/dev/null 2>&1 || true
	fi
	rm -rf "$TEST_TMP"
}
trap cleanup EXIT

fail() {
	echo "[test-build-hxhx-connect-worker] ERROR: $*" >&2
	exit 1
}

cat >"$FAKE_WORKER" <<'FAKE_WORKER'
#!/usr/bin/env bash
set -euo pipefail
trap 'exit 0' TERM INT
while true; do
	:
done
FAKE_WORKER
chmod +x "$FAKE_WORKER"

cat >"$FAKE_HAXE" <<'FAKE_HAXE'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${FAKE_HAXE_TRACE:?}"

if [ "${1:-}" = "--wait" ]; then
	"${FAKE_HAXE_WORKER:?}" --wait 32907 &
	worker_pid="$!"
	printf '%s\n' "$worker_pid" >"${FAKE_HAXE_WORKER_PID_FILE:?}"
	trap 'kill "$worker_pid" >/dev/null 2>&1 || true; exit 0' TERM INT
	wait "$worker_pid"
	exit 0
fi

has_connect=0
has_version=0
for arg in "$@"; do
	if [ "$arg" = "--connect" ]; then
		has_connect=1
	fi
	if [ "$arg" = "--version" ] || [ "$arg" = "-version" ]; then
		has_version=1
	fi
done

if [ "$has_connect" = "1" ] && [ "$has_version" = "1" ]; then
	exit 0
fi

if [ "$has_connect" = "1" ]; then
	sleep 4
	mkdir -p out
	cat >out/dune-project <<'DUNE'
(lang dune 3.0)
DUNE
	cat >out/dune <<'DUNE'
(rule
 (target out.bc)
 (action (write-file %{target} "")))
DUNE
	exit 0
fi

echo "unexpected non-server compile: $*" >&2
exit 91
FAKE_HAXE
chmod +x "$FAKE_HAXE"

(
	cd "$ROOT"
	FAKE_HAXE_TRACE="$TRACE_FILE" \
	FAKE_HAXE_WORKER="$FAKE_WORKER" \
	FAKE_HAXE_WORKER_PID_FILE="$WORKER_PID_FILE" \
	HXHX_STATE_DIR="$STATE_DIR" \
	HXHX_HAXE_SERVER_PORT="$PORT" \
	HXHX_FORCE_STAGE0=1 \
	HAXE_BIN="$FAKE_HAXE" \
	HXHX_STAGE0_USE_REPO_SERVER=1 \
	HXHX_ALLOW_INCOMPLETE_REFLAXE_SERVER_REUSE=1 \
	HXHX_STAGE0_HEARTBEAT=1 \
	HXHX_STAGE0_FAILFAST_SECS=0 \
	HXHX_STAGE0_CONNECT_IDLE_SECS=2 \
		bash scripts/hxhx/build-hxhx.sh >"$OUTPUT_FILE" 2>&1
)

[ -s "$WORKER_PID_FILE" ] || fail "fake server never recorded its worker"
worker_pid="$(cat "$WORKER_PID_FILE")"

if grep -q "rerunning once without --connect after idle-handoff detection" "$OUTPUT_FILE"; then
	fail "healthy worker activity was mistaken for a stalled handoff"
fi
if ! grep -q "server_worker_pid=${worker_pid}" "$OUTPUT_FILE"; then
	sed -n '1,160p' "$OUTPUT_FILE" >&2
	fail "heartbeat did not identify the native server worker"
fi
grep -q "server_tree_cpu=" "$OUTPUT_FILE" \
	|| fail "heartbeat did not report server-tree CPU"

compile_count="$(grep -c '^build\.hxml .*--connect ' "$TRACE_FILE" || true)"
[ "$compile_count" = "1" ] || fail "expected one server compile request, received $compile_count"

if kill -0 "$worker_pid" >/dev/null 2>&1; then
	fail "temporary repository server worker remained alive after the build"
fi
[ ! -e "$STATE_DIR/haxe-server.pid" ] || fail "temporary server PID state remained after the build"
[ ! -e "$STATE_DIR/haxe-server.pids" ] || fail "temporary server process-tree state remained after the build"

last_line="$(tail -n 1 "$OUTPUT_FILE")"
expected_path="$ROOT/packages/hxhx/out/_build/default/out.bc"
[ "$last_line" = "$expected_path" ] || fail "unexpected build output path: $last_line"

echo "BUILD_HXHX_CONNECT_WORKER_SMOKE:PASS"
