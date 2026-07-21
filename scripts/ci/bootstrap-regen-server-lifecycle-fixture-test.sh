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
	shift
	set +e
	PATH="$FAKE_BIN_DIR:$PATH" \
	FAKE_SERVER_PID_CAPTURE="$SERVER_PID_CAPTURE" \
	FAKE_COMPILE_ARGS_CAPTURE="$COMPILE_ARGS_CAPTURE" \
	HXHX_STATE_DIR="$STATE_DIR" \
	HXHX_HAXE_SERVER_PORT="$PORT" \
	HXHX_HAXE_SERVER_PREFLIGHT=0 \
	HXHX_STAGE0_HEARTBEAT=0 \
	HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=prefer-native \
	HXHX_STAGE0_NATIVE_HAXE_BIN="$FAKE_HAXE" \
	HAXE_BIN="$REQUESTED_HAXE" \
		bash "$REGEN_SCRIPT" --incremental --use-repo-server --no-verify --force \
		--report-json "$report_path" "$@" >"$TMP_DIR/regen.log" 2>&1
	local code="$?"
	set -e
	[ "$code" = "23" ] || fail "expected fake compile exit 23, received $code"
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
run_failing_regen "$temporary_report"
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
run_failing_regen "$kept_report" --keep-repo-server
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

echo "BOOTSTRAP_REGEN_SERVER_LIFECYCLE_FIXTURE:PASS"
