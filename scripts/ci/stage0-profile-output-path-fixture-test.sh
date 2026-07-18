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
	printf '%s\n' '{"status":"pass","exit_code":0,"haxe_bin_mode":"native","haxe_bin_policy":"require-native","phase_seconds":{"emit":1,"total":1},"stage0_observability":{"heartbeat_samples":1,"heartbeat_peak_rss_mb":12,"heartbeat_peak_tree_rss_mb":14}}' >"$report_json"

	if [ "${HXHX_STAGE0_PROFILE_FIXTURE_OMIT_PROGRESS:-0}" != "1" ]; then
		mkdir -p -- "$(dirname "$REFLAXE_OCAML_PROGRESS_FILE")"
		printf '%s\n' 'class_end count=1 name=FixtureTarget dt_ms=7' >"$REFLAXE_OCAML_PROGRESS_FILE"
	fi

	mkdir -p -- "$(dirname "$HXHX_STAGE0_HEARTBEAT_TRACE_FILE")"
	printf '%s\n' '{"elapsed_s":1,"pid":1,"focus_pid":1,"rss_mb":12,"tree_rss_mb":14,"cpu_pct":50,"state":"R","log_bytes":64}' >"$HXHX_STAGE0_HEARTBEAT_TRACE_FILE"
	exit 0
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

run_profile() {
	local out_dir="$1"
	shift
	HXHX_STAGE0_PROFILE_REGEN_SCRIPT="$FIXTURE_SCRIPT" \
		HXHX_STAGE0_PROFILE_FIXTURE_REGEN=1 \
		HXHX_STAGE0_PROFILE_FIXTURE_NESTED_DIR="$nested_dir" \
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
[ -s "$caller_dir/$relative_out/reflaxe_ocaml_progress.log" ] || fail "relative progress log was not retained under the caller directory"
[ -s "$caller_dir/$relative_out/progress_summary.json" ] || fail "relative progress summary was not retained under the caller directory"
[ ! -e "$nested_dir/$relative_out" ] || fail "relative artifacts leaked into the nested build directory"

absolute_out="$fixture_root/absolute-artifacts"
run_profile "$absolute_out" >"$fixture_root/absolute.log" 2>&1
[ -s "$absolute_out/regen_report.json" ] || fail "absolute report is missing"
[ -s "$absolute_out/reflaxe_ocaml_progress.log" ] || fail "absolute progress log is missing"
[ -s "$absolute_out/progress_summary.json" ] || fail "absolute progress summary is missing"

missing_out="$fixture_root/missing-progress"
set +e
HXHX_STAGE0_PROFILE_FIXTURE_OMIT_PROGRESS=1 run_profile "$missing_out" >"$fixture_root/missing.log" 2>&1
missing_code="$?"
set -e
[ "$missing_code" = "3" ] || fail "missing progress telemetry returned $missing_code instead of evidence-error exit 3"
if ! grep -F "required progress telemetry is missing or empty" "$fixture_root/missing.log" >/dev/null; then
	fail "missing telemetry diagnostic was not actionable"
fi
if ! grep -F "Profile evidence is incomplete" "$fixture_root/missing.log" >/dev/null; then
	fail "missing telemetry did not explain that evidence is incomplete"
fi

echo "STAGE0_PROFILE_OUTPUT_PATH_FIXTURE:PASS"
