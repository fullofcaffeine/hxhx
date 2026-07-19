#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE_SCRIPT="$ROOT/scripts/hxhx/profile-stage0-regen.sh"
FIXTURE_SCRIPT="$ROOT/scripts/ci/stage0-profile-output-path-fixture-test.sh"

fail() {
	echo "STAGE0_PROFILE_OUTPUT_PATH_FIXTURE:FAIL $*" >&2
	exit 1
}

if [ "${HXHX_STAGE0_PROFILE_FIXTURE_REGEN:-0}" = "1" ]; then
	fixture_exit_code="${HXHX_STAGE0_PROFILE_FIXTURE_EXIT_CODE:-0}"
	fixture_status="ok"
	if [ "$fixture_exit_code" != "0" ]; then
		fixture_status="error"
	fi
	if [ -n "${HXHX_STAGE0_PROFILE_FIXTURE_REGEN_CAPTURE:-}" ]; then
		printf 'regen\n' >>"$HXHX_STAGE0_PROFILE_FIXTURE_REGEN_CAPTURE"
	fi
	if [ "${HXHX_STAGE0_PROFILE_FIXTURE_NESTED_CAPACITY:-0}" = "1" ]; then
		node "$ROOT/scripts/hxhx/check-local-capacity.js" \
			--policy require \
			--wait-seconds 1 \
			--fixture "${HXHX_STAGE0_PROFILE_CAPACITY_FIXTURE:?missing capacity fixture}" \
			--lease-owner-pid "${HXHX_HEAVY_RUN_LEASE_OWNER_PID:?missing inherited lease owner}" \
			--label nested-profile-fixture >"${HXHX_STAGE0_PROFILE_FIXTURE_NESTED_CAPACITY_LOG:?missing nested log}"
	fi
	if [ "${HXHX_STAGE0_PROFILE_FIXTURE_HOLD:-0}" = "1" ]; then
		printf '%s\n' "$$" >"${HXHX_STAGE0_PROFILE_FIXTURE_HOLD_READY:?missing hold-ready path}"
		trap 'exit 143' TERM INT
		while :; do
			sleep 0.1
		done
	fi
	report_json=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--report-json)
				report_json="${2:-}"
				shift 2
				;;
			*)
				shift
				;;
		esac
	done

	[ -n "$report_json" ] || fail "fake regeneration did not receive --report-json"
	cd "${HXHX_STAGE0_PROFILE_FIXTURE_NESTED_DIR:?missing nested fixture directory}"
	mkdir -p -- "$(dirname "$report_json")"
	printf '{"status":"%s","exit_code":%s,"haxe_bin_mode":"native","haxe_bin_policy":"require-native","phase_seconds":{"emit":1,"total":1},"stage0_observability":{"heartbeat_samples":1,"heartbeat_peak_rss_mb":12,"heartbeat_peak_tree_rss_mb":14}}\n' \
		"$fixture_status" "$fixture_exit_code" >"$report_json"

	if [ "${HXHX_STAGE0_PROFILE_FIXTURE_OMIT_PROGRESS:-0}" != "1" ]; then
		mkdir -p -- "$(dirname "$REFLAXE_OCAML_PROGRESS_FILE")"
		printf '%s\n' 'class_end count=1 name=FixtureTarget dt_ms=7' >"$REFLAXE_OCAML_PROGRESS_FILE"
	fi

	mkdir -p -- "$(dirname "$HXHX_STAGE0_HEARTBEAT_TRACE_FILE")"
	printf '%s\n' '{"elapsed_s":1,"pid":1,"focus_pid":1,"rss_mb":12,"tree_rss_mb":14,"cpu_pct":50,"state":"R","log_bytes":64}' >"$HXHX_STAGE0_HEARTBEAT_TRACE_FILE"
	exit "$fixture_exit_code"
fi

[ -x "$PROFILE_SCRIPT" ] || fail "missing profile script"

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/hxhx-stage0-profile-path.XXXXXX")"
cleanup() {
	rm -rf "$fixture_root"
}
trap cleanup EXIT

caller_dir="$fixture_root/caller"
nested_dir="$fixture_root/nested-build"
mkdir -p "$caller_dir" "$nested_dir"
regen_capture="$fixture_root/regen-invocations.log"
idle_capacity_fixture="$fixture_root/capacity-idle.json"
saturated_capacity_fixture="$fixture_root/capacity-saturated.json"
memory_capacity_fixture="$fixture_root/capacity-memory-pressure.json"
printf '%s\n' '{"cpuCount":8,"loadavg":[2,1.5,1],"totalMemoryBytes":17179869184,"freeMemoryBytes":104857600,"availableMemoryBytes":8589934592,"availableMemoryProvenance":"fixture_available","availableMemoryReliable":true,"processes":[]}' >"$idle_capacity_fixture"
printf '%s\n' '{"cpuCount":8,"loadavg":[20,18,10],"totalMemoryBytes":17179869184,"freeMemoryBytes":104857600,"availableMemoryBytes":8589934592,"availableMemoryProvenance":"fixture_available","availableMemoryReliable":true,"processes":[{"pid":101,"parentPid":1,"cpuPercent":98,"elapsed":"04:00","command":"/tool/haxe build"}]}' >"$saturated_capacity_fixture"
printf '%s\n' '{"cpuCount":8,"loadavg":[2,1.5,1],"totalMemoryBytes":17179869184,"freeMemoryBytes":104857600,"availableMemoryBytes":2147483648,"availableMemoryProvenance":"fixture_available","availableMemoryReliable":true,"processes":[]}' >"$memory_capacity_fixture"

run_profile() {
	local out_dir="$1"
	shift
	local capacity_fixture="${HXHX_STAGE0_PROFILE_FIXTURE_CAPACITY_PATH:-$idle_capacity_fixture}"
	HXHX_STAGE0_PROFILE_REGEN_SCRIPT="$FIXTURE_SCRIPT" \
		HXHX_STAGE0_PROFILE_FIXTURE_REGEN=1 \
		HXHX_STAGE0_PROFILE_FIXTURE_NESTED_DIR="$nested_dir" \
		HXHX_STAGE0_PROFILE_FIXTURE_REGEN_CAPTURE="$regen_capture" \
		HXHX_STAGE0_PROFILE_CAPACITY_FIXTURE="$capacity_fixture" \
		bash "$PROFILE_SCRIPT" \
		--policy require-native \
		--failfast 1 \
		--heartbeat 1 \
		--scenario-args "" \
		--out-dir "$out_dir" \
		"$@"
}

cd "$caller_dir"
relative_out="relative artifacts"
run_profile "$relative_out" >"$fixture_root/relative.log" 2>&1
[ -s "$caller_dir/$relative_out/regen_report.json" ] || fail "relative report was not retained under the caller directory"
[ -s "$caller_dir/$relative_out/capacity_report.json" ] || fail "capacity evidence was not retained with the profile"
[ -s "$caller_dir/$relative_out/reflaxe_ocaml_progress.log" ] || fail "relative progress log was not retained under the caller directory"
[ -s "$caller_dir/$relative_out/progress_summary.json" ] || fail "relative progress summary was not retained under the caller directory"
[ ! -e "$nested_dir/$relative_out" ] || fail "relative artifacts leaked into the nested build directory"

absolute_out="$fixture_root/absolute-artifacts"
run_profile "$absolute_out" >"$fixture_root/absolute.log" 2>&1
[ -s "$absolute_out/regen_report.json" ] || fail "absolute report is missing"
[ -s "$absolute_out/reflaxe_ocaml_progress.log" ] || fail "absolute progress log is missing"
[ -s "$absolute_out/progress_summary.json" ] || fail "absolute progress summary is missing"

failed_out="$fixture_root/failed-regeneration"
set +e
HXHX_STAGE0_PROFILE_FIXTURE_EXIT_CODE=17 \
	run_profile "$failed_out" >"$fixture_root/failed.log" 2>&1
failed_code="$?"
set -e
[ "$failed_code" = "17" ] || fail "failed regeneration returned $failed_code instead of its real exit code 17"
[ -s "$failed_out/regen_report.json" ] || fail "failed regeneration did not retain its report"
[ -s "$failed_out/progress_summary.json" ] || fail "failed regeneration did not retain its progress summary"
grep -F "Summary artifacts are still available" "$fixture_root/failed.log" >/dev/null \
	|| fail "failed regeneration did not explain that diagnostics were retained"

queued_out="$fixture_root/queued-artifacts"
queued_lease="$fixture_root/shared-heavy-run.lease.json"
queued_nested_log="$fixture_root/nested-capacity.log"
HXHX_HEAVY_RUN_WAIT_SECONDS=1 \
	HXHX_HEAVY_RUN_POLL_SECONDS=0.01 \
	HXHX_HEAVY_RUN_LEASE_FILE="$queued_lease" \
	HXHX_STAGE0_PROFILE_FIXTURE_NESTED_CAPACITY=1 \
	HXHX_STAGE0_PROFILE_FIXTURE_NESTED_CAPACITY_LOG="$queued_nested_log" \
	run_profile "$queued_out" >"$fixture_root/queued.log" 2>&1
[ ! -e "$queued_lease" ] || fail "successful queued profile did not release its cooperative lease"
grep -F "HXHX_LOCAL_CAPACITY:PASS" "$queued_nested_log" >/dev/null \
	|| fail "nested profile capacity check did not reuse the outer lease"
node -e '
const fs = require("fs")
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
if (report.queue.outcome !== "admitted_immediately" || report.lease.status !== "acquired") process.exit(1)
' "$queued_out/capacity_report.json" || fail "queued profile report did not record lease admission"

missing_out="$fixture_root/missing-progress"
missing_lease="$fixture_root/missing-progress.lease.json"
set +e
HXHX_HEAVY_RUN_WAIT_SECONDS=1 \
	HXHX_HEAVY_RUN_POLL_SECONDS=0.01 \
	HXHX_HEAVY_RUN_LEASE_FILE="$missing_lease" \
	HXHX_STAGE0_PROFILE_FIXTURE_OMIT_PROGRESS=1 \
	run_profile "$missing_out" >"$fixture_root/missing.log" 2>&1
missing_code="$?"
set -e
[ "$missing_code" = "3" ] || fail "missing progress telemetry returned $missing_code instead of evidence-error exit 3"
[ ! -e "$missing_lease" ] || fail "failed queued profile did not release its cooperative lease"
if ! grep -F "required progress telemetry is missing or empty" "$fixture_root/missing.log" >/dev/null; then
	fail "missing telemetry diagnostic was not actionable"
fi
if ! grep -F "Profile evidence is incomplete" "$fixture_root/missing.log" >/dev/null; then
	fail "missing telemetry did not explain that evidence is incomplete"
fi

blocked_out="$fixture_root/blocked-capacity"
before_regen_count="$(wc -l <"$regen_capture" | tr -d ' ')"
set +e
HXHX_STAGE0_PROFILE_FIXTURE_CAPACITY_PATH="$saturated_capacity_fixture" \
	run_profile "$blocked_out" >"$fixture_root/blocked.log" 2>&1
blocked_code="$?"
set -e
[ "$blocked_code" = "75" ] || fail "saturated capacity returned $blocked_code instead of retryable exit 75"
after_regen_count="$(wc -l <"$regen_capture" | tr -d ' ')"
[ "$after_regen_count" = "$before_regen_count" ] || fail "saturated capacity invoked expensive regeneration"
[ -s "$blocked_out/capacity_report.json" ] || fail "blocked profile did not retain its capacity report"
[ ! -e "$blocked_out/regen_report.json" ] || fail "blocked profile unexpectedly produced a regeneration report"
node -e '
const fs = require("fs")
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
if (report.status !== "blocked" || report.exitCode !== 75) process.exit(1)
' "$blocked_out/capacity_report.json" || fail "blocked capacity report did not preserve the decision"
grep -F "HXHX_LOCAL_CAPACITY:BLOCKED" "$fixture_root/blocked.log" >/dev/null \
	|| fail "blocked profile did not explain why work stopped"

memory_blocked_out="$fixture_root/blocked-memory-capacity"
before_memory_regen_count="$(wc -l <"$regen_capture" | tr -d ' ')"
set +e
HXHX_STAGE0_PROFILE_FIXTURE_CAPACITY_PATH="$memory_capacity_fixture" \
	run_profile "$memory_blocked_out" >"$fixture_root/blocked-memory.log" 2>&1
memory_blocked_code="$?"
set -e
[ "$memory_blocked_code" = "75" ] \
	|| fail "memory-only capacity pressure returned $memory_blocked_code instead of retryable exit 75"
after_memory_regen_count="$(wc -l <"$regen_capture" | tr -d ' ')"
[ "$after_memory_regen_count" = "$before_memory_regen_count" ] \
	|| fail "memory-only capacity pressure invoked expensive regeneration"
grep -F "observations=available_memory" "$fixture_root/blocked-memory.log" >/dev/null \
	|| fail "memory-only block did not identify available-memory pressure"

cancelled_out="$fixture_root/cancelled-profile"
cancelled_lease="$fixture_root/cancelled-profile.lease.json"
cancelled_ready="$fixture_root/cancelled-profile.ready"
HXHX_HEAVY_RUN_WAIT_SECONDS=1 \
	HXHX_HEAVY_RUN_POLL_SECONDS=0.01 \
	HXHX_HEAVY_RUN_LEASE_FILE="$cancelled_lease" \
	HXHX_STAGE0_PROFILE_REGEN_SCRIPT="$FIXTURE_SCRIPT" \
	HXHX_STAGE0_PROFILE_FIXTURE_REGEN=1 \
	HXHX_STAGE0_PROFILE_FIXTURE_NESTED_DIR="$nested_dir" \
	HXHX_STAGE0_PROFILE_FIXTURE_REGEN_CAPTURE="$regen_capture" \
	HXHX_STAGE0_PROFILE_CAPACITY_FIXTURE="$idle_capacity_fixture" \
	HXHX_STAGE0_PROFILE_FIXTURE_HOLD=1 \
	HXHX_STAGE0_PROFILE_FIXTURE_HOLD_READY="$cancelled_ready" \
	bash "$PROFILE_SCRIPT" \
		--policy require-native \
		--failfast 1 \
		--heartbeat 1 \
		--scenario-args "" \
		--out-dir "$cancelled_out" >"$fixture_root/cancelled.log" 2>&1 &
cancelled_profile_pid="$!"
for _attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	if [ -s "$cancelled_ready" ] && [ -s "$cancelled_lease" ]; then
		break
	fi
	sleep 0.05
done
[ -s "$cancelled_ready" ] || fail "cancelled profile fixture never entered its held child"
[ -s "$cancelled_lease" ] || fail "cancelled profile fixture never acquired its lease"
cancelled_child_pid="$(cat "$cancelled_ready")"
kill -TERM "$cancelled_profile_pid" 2>/dev/null || true
kill -TERM "$cancelled_child_pid" 2>/dev/null || true
wait "$cancelled_profile_pid" 2>/dev/null || true
[ ! -e "$cancelled_lease" ] || fail "cancelled profile did not release its cooperative lease"

echo "STAGE0_PROFILE_OUTPUT_PATH_FIXTURE:PASS"
