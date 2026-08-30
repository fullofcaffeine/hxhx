#!/usr/bin/env bash
set -euo pipefail

# Exercises bootstrap-regeneration server cleanup without touching generated
# output. The fake Haxe server starts normally, while the fake compile client
# fails immediately so both report preservation and EXIT cleanup are tested.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGEN_SCRIPT="$ROOT/scripts/hxhx/regenerate-hxhx-bootstrap.sh"
SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hxhx-bootstrap-server-lifecycle.XXXXXX")"
STATE_DIR="$TMP_DIR/state"
FAKE_BIN_DIR="$TMP_DIR/bin"
FAKE_HAXE="$FAKE_BIN_DIR/fake-haxe"
REQUESTED_HAXE="$FAKE_BIN_DIR/requested-haxe-wrapper"
SERVER_PID_CAPTURE="$TMP_DIR/server.pid"
SERVER_CHILD_CAPTURE="$TMP_DIR/server-child.pid"
COMPILE_ARGS_CAPTURE="$TMP_DIR/compile-args.txt"
PORT=31874

cleanup() {
	HXHX_STATE_DIR="$STATE_DIR" HXHX_HAXE_SERVER_PORT="$PORT" HAXE_BIN="$FAKE_HAXE" \
		bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
	echo "[bootstrap-regen-server-lifecycle-fixture-test] ERROR: $*" >&2
	exit 1
}

mkdir -p "$FAKE_BIN_DIR"
cat >"$FAKE_HAXE" <<'FAKE_HAXE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--wait" ]; then
	printf '%s\n' "$$" >"$FAKE_SERVER_PID_CAPTURE"
	worker_pid=""
	stop_server() {
		if [ -n "$worker_pid" ]; then
			kill -TERM "$worker_pid" >/dev/null 2>&1 || true
			wait "$worker_pid" >/dev/null 2>&1 || true
		fi
		exit 0
	}
	trap stop_server TERM INT
	case "${FAKE_SERVER_MODE:-idle}" in
		busy)
			node -e 'const retained = Buffer.alloc(64 * 1024 * 1024, 1); while (true) retained[0] ^= 1' &
			;;
		idle)
			tail -f /dev/null &
			;;
		*)
			echo "unknown fake server mode: ${FAKE_SERVER_MODE:-}" >&2
			exit 96
			;;
	esac
	worker_pid="$!"
	printf '%s\n' "$worker_pid" >"$FAKE_SERVER_CHILD_CAPTURE"
	wait "$worker_pid"
fi
has_connect=0
has_version=0
for arg in "$@"; do
	[ "$arg" = "--connect" ] && has_connect=1
	[ "$arg" = "--version" ] || [ "$arg" = "-version" ] && has_version=1
done
if [ "$has_version" = "1" ]; then
	echo "4.3.7"
	exit 0
fi
if [ "$has_connect" = "1" ]; then
	case "${FAKE_COMPILE_MODE:-immediate}" in
		immediate) ;;
		sleep-four) sleep 4 ;;
		sleep-long) sleep 20 ;;
		*)
			echo "unknown fake compile mode: ${FAKE_COMPILE_MODE:-}" >&2
			exit 95
			;;
	esac
fi
printf '%s\n' "$@" >"$FAKE_COMPILE_ARGS_CAPTURE"
exit 23
FAKE_HAXE_SCRIPT
chmod +x "$FAKE_HAXE"

cat >"$REQUESTED_HAXE" <<'REQUESTED_HAXE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-version" ]; then
	echo "4.3.7"
	exit 0
fi
echo "requested wrapper must not run the server or compile after native selection: $*" >&2
exit 97
REQUESTED_HAXE_SCRIPT
chmod +x "$REQUESTED_HAXE"

for tool in dune ocamlc; do
	cat >"$FAKE_BIN_DIR/$tool" <<'FAKE_TOOL'
#!/usr/bin/env bash
exit 0
FAKE_TOOL
	chmod +x "$FAKE_BIN_DIR/$tool"
done

run_failing_regen() {
	local report_path="$1"
	local expected_code="$2"
	local server_mode="$3"
	local compile_mode="$4"
	local log_name="$5"
	local connection_mode="$6"
	shift 6
	local connect_endpoint=""
	local -a regen_args=(--incremental --no-verify --force)
	case "$connection_mode" in
		repo) regen_args+=(--use-repo-server) ;;
		manual) connect_endpoint="$PORT" ;;
		*) fail "unknown connection mode: $connection_mode" ;;
	esac
	set +e
	PATH="$FAKE_BIN_DIR:$PATH" \
	FAKE_SERVER_PID_CAPTURE="$SERVER_PID_CAPTURE" \
	FAKE_SERVER_CHILD_CAPTURE="$SERVER_CHILD_CAPTURE" \
	FAKE_COMPILE_ARGS_CAPTURE="$COMPILE_ARGS_CAPTURE" \
	FAKE_SERVER_MODE="$server_mode" \
	FAKE_COMPILE_MODE="$compile_mode" \
	HXHX_STATE_DIR="$STATE_DIR" \
	HXHX_HAXE_SERVER_PORT="$PORT" \
	HXHX_HAXE_SERVER_PREFLIGHT=0 \
	HXHX_STAGE0_HEARTBEAT=1 \
	HXHX_STAGE0_HEARTBEAT_TRACE_FILE="$TMP_DIR/$log_name.trace.jsonl" \
	HXHX_STAGE0_PROGRESS_POLL_SECS=1 \
	HXHX_STAGE0_STALL_TIMEOUT_SECS=2 \
	HXHX_STAGE0_FAILFAST_SECS=10 \
	HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=prefer-native \
	HXHX_STAGE0_NATIVE_HAXE_BIN="$FAKE_HAXE" \
	HAXE_CONNECT="$connect_endpoint" \
	HAXE_BIN="$REQUESTED_HAXE" \
		bash "$REGEN_SCRIPT" "${regen_args[@]}" \
		--report-json "$report_path" "$@" >"$TMP_DIR/$log_name.log" 2>&1
	local code="$?"
	set -e
	[ "$code" = "$expected_code" ] \
		|| fail "$log_name expected fake compile exit $expected_code, received $code"
}

assert_failure_report() {
	local report_path="$1"
	[ -s "$report_path" ] || fail "failed regeneration did not preserve its JSON report"
	node -e '
const fs = require("fs")
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
if (report.status !== "error" || report.exit_code !== 23) process.exit(1)
' "$report_path" || fail "failure report did not preserve status=error and exit_code=23"
}

temporary_report="$TMP_DIR/temporary-server-report.json"
run_failing_regen "$temporary_report" 23 idle immediate temporary repo
assert_failure_report "$temporary_report"
grep -Fx -- "reflaxe.dont_output_metadata_id" "$COMPILE_ARGS_CAPTURE" >/dev/null \
	|| fail "regeneration did not request stable Reflaxe output metadata"
temporary_server_pid="$(cat "$SERVER_PID_CAPTURE")"
[ ! -e "$STATE_DIR/haxe-server.pid" ] || fail "temporary run left its server PID state behind"
[ ! -e "$STATE_DIR/haxe-server.bin" ] || fail "temporary run left its server identity state behind"
if kill -0 "$temporary_server_pid" >/dev/null 2>&1; then
	fail "temporary run left its server process alive"
fi

kept_report="$TMP_DIR/kept-server-report.json"
run_failing_regen "$kept_report" 23 idle immediate kept repo --keep-repo-server
assert_failure_report "$kept_report"
kept_server_pid="$(cat "$STATE_DIR/haxe-server.pid")"
kill -0 "$kept_server_pid" >/dev/null 2>&1 || fail "--keep-repo-server did not keep the server alive"
expected_server_identity="$(cd "$(dirname "$FAKE_HAXE")" && pwd -P)/$(basename "$FAKE_HAXE")"
actual_server_identity="$(cat "$STATE_DIR/haxe-server.bin")"
[ "$actual_server_identity" = "$expected_server_identity" ] \
	|| fail "repo server used $actual_server_identity instead of selected Haxe $expected_server_identity"

HXHX_STATE_DIR="$STATE_DIR" HXHX_HAXE_SERVER_PORT="$PORT" HAXE_BIN="$FAKE_HAXE" \
	bash "$SERVER_HELPER" stop >/dev/null
[ ! -e "$STATE_DIR/haxe-server.pid" ] || fail "explicit stop left PID state behind"
[ ! -e "$STATE_DIR/haxe-server.bin" ] || fail "explicit stop left identity state behind"

# A manually supplied endpoint has no repository ownership receipt. The client
# still runs, but the watchdog must not classify that external server as owned.
manual_report="$TMP_DIR/manual-connect-report.json"
run_failing_regen "$manual_report" 23 idle immediate manual-connect manual
assert_failure_report "$manual_report"
grep -Fq '"connected_server_observed": false' "$manual_report" \
	|| fail "manual --connect endpoint was classified as a repository-owned server"
[ ! -e "$STATE_DIR/haxe-server.pid" ] || fail "manual --connect unexpectedly created repo server state"

# The connected client sleeps while the exact repository-owned server performs
# CPU- and memory-heavy work. The soft stall timer must observe that server
# worker, and telemetry must include its retained memory.
busy_report="$TMP_DIR/busy-server-report.json"
run_failing_regen "$busy_report" 23 busy sleep-four busy repo
assert_failure_report "$busy_report"
node -e '
const fs = require("fs")
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
const trace = fs.readFileSync(process.argv[2], "utf8").trim().split("\n").map(JSON.parse)
const observed = report.stage0_observability
if (observed.connected_server_observed !== true) process.exit(1)
if (observed.last_progress_reason !== "cpu-time") process.exit(1)
if (observed.heartbeat_peak_tree_rss_mb < 32) process.exit(1)
if (!trace.some(sample => sample.owned_server_pids.length > 0)) process.exit(1)
' "$busy_report" "$TMP_DIR/busy.trace.jsonl" \
	|| fail "busy owned server was absent from watchdog progress or memory telemetry"

# A connected client and server that are both idle still hit the soft limit.
# Timeout cleanup overrides --keep-repo-server because the request cannot be
# detached safely from this single owned server.
idle_report="$TMP_DIR/idle-server-report.json"
run_failing_regen "$idle_report" 124 idle sleep-long idle-timeout repo --keep-repo-server
idle_server_pid="$(cat "$SERVER_PID_CAPTURE")"
idle_server_child_pid="$(cat "$SERVER_CHILD_CAPTURE")"
[ ! -e "$STATE_DIR/haxe-server.pid" ] || fail "timed-out request retained owned server state"
if kill -0 "$idle_server_pid" >/dev/null 2>&1 || kill -0 "$idle_server_child_pid" >/dev/null 2>&1; then
	fail "timed-out request left an owned server process consuming resources"
fi
grep -Fq '"timeout_kind": "stall"' "$idle_report" \
	|| fail "idle connected server did not retain its stall result"
grep -Fq '"timeout_cleanup": "complete"' "$idle_report" \
	|| fail "idle connected server did not report complete cleanup"

echo "BOOTSTRAP_REGEN_SERVER_LIFECYCLE_FIXTURE:PASS"
