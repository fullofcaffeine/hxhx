#!/usr/bin/env bash
set -euo pipefail

# Proves that bootstrap regeneration distinguishes a quiet but CPU-active
# compiler from a process that has stopped making observable progress.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGEN_SCRIPT="$ROOT/scripts/hxhx/regenerate-hxhx-bootstrap.sh"
WATCHDOG_SCRIPT="$ROOT/scripts/hxhx/stage0-process-watchdog.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hxhx-bootstrap-watchdog.XXXXXX")"
FAKE_BIN_DIR="$TMP_DIR/bin"
FAKE_HAXE="$FAKE_BIN_DIR/haxe"
TREE_ROOT_PID=""

cleanup() {
	if [ -n "$TREE_ROOT_PID" ]; then
		stage0_watchdog_terminate_process_tree "$TREE_ROOT_PID" 2>/dev/null || true
		wait "$TREE_ROOT_PID" >/dev/null 2>&1 || true
	fi
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
	echo "[bootstrap-regen-watchdog-fixture-test] ERROR: $*" >&2
	exit 1
}

mkdir -p "$FAKE_BIN_DIR"
source "$WATCHDOG_SCRIPT"

# A compiler can briefly own many helper processes. Process-tree observation
# must remain bounded and include those descendants instead of chasing a
# changing process table indefinitely.
bash -c 'trap "exit 0" TERM; for _ in $(seq 1 80); do sleep 20 & done; wait' >/dev/null 2>&1 &
TREE_ROOT_PID="$!"
for _ in $(seq 1 20); do
	[ "$(pgrep -P "$TREE_ROOT_PID" 2>/dev/null | wc -l | tr -d ' ')" -ge 80 ] && break
	sleep 0.1
done
tree_start="$(date +%s)"
tree_pids="$(stage0_watchdog_collect_process_tree_pids "$TREE_ROOT_PID")"
tree_elapsed="$(($(date +%s) - tree_start))"
[ "$tree_elapsed" -lt 5 ] \
	|| fail "process-tree collection took ${tree_elapsed}s; expected a bounded snapshot"
[ "$(wc -w <<<"$tree_pids" | tr -d ' ')" -ge 81 ] \
	|| fail "process-tree collection omitted high-fan-out descendants"
stage0_watchdog_terminate_process_tree "$TREE_ROOT_PID"
wait "$TREE_ROOT_PID" >/dev/null 2>&1 || true
TREE_ROOT_PID=""

cat >"$FAKE_HAXE" <<'FAKE_HAXE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-version" ]; then
	echo "4.3.7"
	exit 0
fi

case "${FAKE_STAGE0_MODE:-}" in
	cpu-progress)
		end="$((SECONDS + 4))"
		while [ "$SECONDS" -lt "$end" ]; do
			:
		done
		exit 23
		;;
	stalled)
		sleep 20
		exit 24
		;;
	hard-limit)
		end="$((SECONDS + 20))"
		while [ "$SECONDS" -lt "$end" ]; do
			:
		done
		exit 25
		;;
	*)
		echo "missing FAKE_STAGE0_MODE" >&2
		exit 97
		;;
esac
FAKE_HAXE_SCRIPT
chmod +x "$FAKE_HAXE"

for tool in dune ocamlc; do
	cat >"$FAKE_BIN_DIR/$tool" <<'FAKE_TOOL'
#!/usr/bin/env bash
exit 0
FAKE_TOOL
	chmod +x "$FAKE_BIN_DIR/$tool"
done

run_case() {
	local mode="$1"
	local stall_seconds="$2"
	local hard_seconds="$3"
	local expected_code="$4"
	local log_path="$TMP_DIR/$mode.log"
	local report_path="$TMP_DIR/$mode.report.json"

	set +e
	PATH="$FAKE_BIN_DIR:$PATH" \
	HAXE_BIN="$FAKE_HAXE" \
	FAKE_STAGE0_MODE="$mode" \
	HXHX_HAXE_SERVER_PREFLIGHT=0 \
	HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=warn \
	HXHX_STAGE0_HEARTBEAT=1 \
	HXHX_STAGE0_PROGRESS_POLL_SECS=1 \
	HXHX_STAGE0_STALL_TIMEOUT_SECS="$stall_seconds" \
	HXHX_STAGE0_FAILFAST_SECS="$hard_seconds" \
		bash "$REGEN_SCRIPT" --incremental --no-verify --force \
			--report-json "$report_path" >"$log_path" 2>&1
	local code="$?"
	set -e

	[ "$code" = "$expected_code" ] \
		|| fail "$mode exited $code; expected $expected_code (log: $log_path)"
	[ -s "$report_path" ] || fail "$mode did not preserve its JSON report"
}

# The fake compiler writes no log output, but consumes CPU for longer than the
# two-second stall limit. It must reach its own exit code instead of being
# mistaken for a hang.
run_case cpu-progress 2 10 23
grep -Fq 'last_progress_reason=cpu-time' "$TMP_DIR/cpu-progress.log" \
	|| fail "CPU-active case did not report CPU time as progress"
grep -Fq '"last_progress_reason": "cpu-time"' "$TMP_DIR/cpu-progress.report.json" \
	|| fail "CPU-active report did not preserve the last progress reason"

# A sleeping compiler consumes no CPU and writes no output. The stall watchdog
# must stop it before the absolute ceiling.
run_case stalled 2 10 124
grep -Fq 'timeout=stall' "$TMP_DIR/stalled.log" \
	|| fail "stalled case did not report the stall timeout"
grep -Fq 'cleanup=complete' "$TMP_DIR/stalled.log" \
	|| fail "stalled case did not report deterministic cleanup"
grep -Eq 'process_tree="[0-9]+ [0-9]+' "$TMP_DIR/stalled.log" \
	|| fail "stalled case did not observe and stop the compiler child process"
grep -Fq '"timeout_kind": "stall"' "$TMP_DIR/stalled.report.json" \
	|| fail "stalled report did not preserve the timeout kind"
grep -Fq '"timeout_cleanup": "complete"' "$TMP_DIR/stalled.report.json" \
	|| fail "stalled report did not preserve the cleanup result"

# Observable CPU work can extend the soft limit, but never the absolute limit.
run_case hard-limit 2 3 124
grep -Fq 'timeout=hard' "$TMP_DIR/hard-limit.log" \
	|| fail "CPU-active hard-limit case did not report the absolute timeout"
grep -Fq 'cleanup=complete' "$TMP_DIR/hard-limit.log" \
	|| fail "hard-limit case did not report deterministic cleanup"
grep -Fq '"timeout_kind": "hard"' "$TMP_DIR/hard-limit.report.json" \
	|| fail "hard-limit report did not preserve the timeout kind"

echo "BOOTSTRAP_REGEN_WATCHDOG_FIXTURE:PASS"
