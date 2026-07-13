#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGEN_SCRIPT="$ROOT/scripts/hxhx/regenerate-hxhx-bootstrap.sh"
SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
REPORT_BUILDER="$ROOT/scripts/ci/bootstrap-regen-benchmark-report.js"

HAXE_BIN="${HAXE_BIN:-haxe}"
REPS="${HXHX_BOOTSTRAP_BENCH_REPS:-1}"
SCENARIOS_RAW="${HXHX_BOOTSTRAP_BENCH_SCENARIOS:-cold,warm,skip}"
VERIFY_FLAG="${HXHX_BOOTSTRAP_BENCH_VERIFY:-0}"
STAGE0_POLICY="${HXHX_BOOTSTRAP_BENCH_STAGE0_HAXE_POLICY:-}"
STAGE0_NATIVE_BIN="${HXHX_BOOTSTRAP_BENCH_STAGE0_NATIVE_HAXE_BIN:-}"
COMPARE_STAGE0_POLICIES="${HXHX_BOOTSTRAP_BENCH_COMPARE_STAGE0_POLICIES:-0}"
DUNE_JOBS_RAW="${HXHX_BOOTSTRAP_BENCH_DUNE_JOBS:-auto}"
STAGE0_NO_OPT="${HXHX_BOOTSTRAP_BENCH_STAGE0_NO_OPT:-0}"
STAGE0_NO_INLINE="${HXHX_BOOTSTRAP_BENCH_STAGE0_NO_INLINE:-0}"
STAGE0_DISABLE_PREPASSES="${HXHX_BOOTSTRAP_BENCH_STAGE0_DISABLE_PREPASSES:-0}"
STAGE0_OCAMLRUNPARAM="${HXHX_BOOTSTRAP_BENCH_STAGE0_OCAMLRUNPARAM:-}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_DIR="${HXHX_BOOTSTRAP_BENCH_REPORT_DIR:-$ROOT/.hxhx/bench/bootstrap-regen/$TIMESTAMP}"
REPORT_JSON="$REPORT_DIR/report.json"

SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
if git -C "$ROOT" diff --quiet --ignore-submodules -- \
	&& git -C "$ROOT" diff --cached --quiet --ignore-submodules --; then
	SOURCE_CLEAN_AT_START="true"
else
	SOURCE_CLEAN_AT_START="false"
fi

usage() {
	cat <<'USAGE'
Usage: bash scripts/hxhx/bench-bootstrap-regen.sh

Environment knobs:
  HAXE_BIN                             Haxe executable path (default: haxe)
  HXHX_BOOTSTRAP_BENCH_REPS           Repetitions per scenario (default: 1)
  HXHX_BOOTSTRAP_BENCH_SCENARIOS      Comma list: cold,warm,skip,select (default: cold,warm,skip)
  HXHX_BOOTSTRAP_BENCH_VERIFY         0/1 run snapshot verify step (default: 0)
  HXHX_BOOTSTRAP_BENCH_STAGE0_HAXE_POLICY
                                      Stage0 haxe policy override for all runs
                                      (warn|prefer-native|require-native)
  HXHX_BOOTSTRAP_BENCH_STAGE0_NATIVE_HAXE_BIN
                                      Native haxe candidate override used by regen script
  HXHX_BOOTSTRAP_BENCH_COMPARE_STAGE0_POLICIES
                                      0/1 run each benchmark twice:
                                      wrapper=warn and native=prefer-native
  HXHX_BOOTSTRAP_BENCH_DUNE_JOBS      Comma list of dune worker settings
                                      (values: auto or positive integers, default: auto)
  HXHX_BOOTSTRAP_BENCH_STAGE0_NO_OPT
                                      0/1 pass HXHX_STAGE0_NO_OPT to regen runs
  HXHX_BOOTSTRAP_BENCH_STAGE0_NO_INLINE
                                      0/1 pass HXHX_STAGE0_NO_INLINE to regen runs
  HXHX_BOOTSTRAP_BENCH_STAGE0_DISABLE_PREPASSES
                                      0/1 pass HXHX_STAGE0_DISABLE_PREPASSES to regen runs
  HXHX_BOOTSTRAP_BENCH_STAGE0_OCAMLRUNPARAM
                                      pass HXHX_STAGE0_OCAMLRUNPARAM to regen runs
  HXHX_BOOTSTRAP_BENCH_REPORT_DIR     Output directory for per-run JSON reports

Outputs:
  results.tsv                         Raw run rows
  <scenario>.<policy>.*.json          Low-level regeneration reports
  report.json                         Self-describing report with medians and provenance

Examples:
  # Run warm + skip only (faster local loop)
  HXHX_BOOTSTRAP_BENCH_SCENARIOS=warm,skip bash scripts/hxhx/bench-bootstrap-regen.sh

  # Include verify and 2 reps
  HXHX_BOOTSTRAP_BENCH_VERIFY=1 HXHX_BOOTSTRAP_BENCH_REPS=2 bash scripts/hxhx/bench-bootstrap-regen.sh

  # Compare wrapper vs native stage0 policy on warm path
  HXHX_BOOTSTRAP_BENCH_SCENARIOS=warm HXHX_BOOTSTRAP_BENCH_COMPARE_STAGE0_POLICIES=1 \
    bash scripts/hxhx/bench-bootstrap-regen.sh
USAGE
}

is_non_negative_int() {
	case "$1" in
		''|*[!0-9]*)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

trim_token() {
	echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

is_valid_dune_jobs_token() {
	local value="$1"
	case "$value" in
		auto)
			return 0
			;;
		''|*[!0-9]*|0)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	usage
	exit 0
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
	echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
	exit 1
fi

if ! command -v node >/dev/null 2>&1; then
	echo "Missing node on PATH (required for the benchmark report)." >&2
	exit 1
fi

if [ ! -x "$REGEN_SCRIPT" ]; then
	echo "Missing regen script: $REGEN_SCRIPT" >&2
	exit 1
fi

if [ ! -x "$SERVER_HELPER" ]; then
	echo "Missing haxe server helper: $SERVER_HELPER" >&2
	exit 1
fi

if [ ! -f "$REPORT_BUILDER" ]; then
	echo "Missing report builder: $REPORT_BUILDER" >&2
	exit 1
fi

if ! is_non_negative_int "$REPS" || [ "$REPS" = "0" ]; then
	echo "Invalid HXHX_BOOTSTRAP_BENCH_REPS: '$REPS' (expected positive integer)." >&2
	exit 1
fi

if ! is_non_negative_int "$VERIFY_FLAG"; then
	echo "Invalid HXHX_BOOTSTRAP_BENCH_VERIFY: '$VERIFY_FLAG' (expected 0 or 1)." >&2
	exit 1
fi

if ! is_non_negative_int "$COMPARE_STAGE0_POLICIES"; then
	echo "Invalid HXHX_BOOTSTRAP_BENCH_COMPARE_STAGE0_POLICIES: '$COMPARE_STAGE0_POLICIES' (expected 0 or 1)." >&2
	exit 1
fi
if ! is_non_negative_int "$STAGE0_NO_OPT"; then
	echo "Invalid HXHX_BOOTSTRAP_BENCH_STAGE0_NO_OPT: '$STAGE0_NO_OPT' (expected 0 or 1)." >&2
	exit 1
fi
if ! is_non_negative_int "$STAGE0_NO_INLINE"; then
	echo "Invalid HXHX_BOOTSTRAP_BENCH_STAGE0_NO_INLINE: '$STAGE0_NO_INLINE' (expected 0 or 1)." >&2
	exit 1
fi
if ! is_non_negative_int "$STAGE0_DISABLE_PREPASSES"; then
	echo "Invalid HXHX_BOOTSTRAP_BENCH_STAGE0_DISABLE_PREPASSES: '$STAGE0_DISABLE_PREPASSES' (expected 0 or 1)." >&2
	exit 1
fi
if [ "$STAGE0_NO_OPT" != "0" ] && [ "$STAGE0_NO_OPT" != "1" ]; then
	echo "Invalid HXHX_BOOTSTRAP_BENCH_STAGE0_NO_OPT: '$STAGE0_NO_OPT' (expected 0 or 1)." >&2
	exit 1
fi
if [ "$STAGE0_NO_INLINE" != "0" ] && [ "$STAGE0_NO_INLINE" != "1" ]; then
	echo "Invalid HXHX_BOOTSTRAP_BENCH_STAGE0_NO_INLINE: '$STAGE0_NO_INLINE' (expected 0 or 1)." >&2
	exit 1
fi
if [ "$STAGE0_DISABLE_PREPASSES" != "0" ] && [ "$STAGE0_DISABLE_PREPASSES" != "1" ]; then
	echo "Invalid HXHX_BOOTSTRAP_BENCH_STAGE0_DISABLE_PREPASSES: '$STAGE0_DISABLE_PREPASSES' (expected 0 or 1)." >&2
	exit 1
fi

if [ "$COMPARE_STAGE0_POLICIES" = "1" ] && [ -n "$STAGE0_POLICY" ]; then
	echo "Cannot set HXHX_BOOTSTRAP_BENCH_STAGE0_HAXE_POLICY when HXHX_BOOTSTRAP_BENCH_COMPARE_STAGE0_POLICIES=1." >&2
	exit 1
fi

if [ -n "$STAGE0_POLICY" ]; then
	case "$STAGE0_POLICY" in
		warn|prefer-native|require-native)
			;;
		*)
			echo "Invalid HXHX_BOOTSTRAP_BENCH_STAGE0_HAXE_POLICY: '$STAGE0_POLICY' (expected warn|prefer-native|require-native)." >&2
			exit 1
			;;
	esac
fi

DUNE_JOBS_LIST=()
IFS=',' read -r -a dune_jobs_tokens <<<"$DUNE_JOBS_RAW"
for token in "${dune_jobs_tokens[@]}"; do
	token="$(trim_token "$token")"
	if [ -z "$token" ]; then
		continue
	fi
	if ! is_valid_dune_jobs_token "$token"; then
		echo "Invalid HXHX_BOOTSTRAP_BENCH_DUNE_JOBS token: '$token' (expected auto or a positive integer)." >&2
		exit 1
	fi
	DUNE_JOBS_LIST+=("$token")
done
if [ "${#DUNE_JOBS_LIST[@]}" -eq 0 ]; then
	echo "HXHX_BOOTSTRAP_BENCH_DUNE_JOBS produced no valid values." >&2
	exit 1
fi

mkdir -p "$REPORT_DIR"
RESULTS_TSV="$REPORT_DIR/results.tsv"
printf 'scenario\tpolicy\tdune_jobs\trep\telapsed_sec\temit_sec\ttotal_sec\tskipped_emit\thaxe_mode\thaxe_policy\tswitched\tpeak_rss_mb\treport\n' >"$RESULTS_TSV"

cleanup() {
	bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true

verify_args=(--no-verify)
if [ "$VERIFY_FLAG" = "1" ]; then
	verify_args=(--verify)
fi

echo "== hxhx bootstrap regen benchmark"
echo "HAXE_BIN: $HAXE_BIN"
echo "Scenarios: $SCENARIOS_RAW"
echo "Reps per scenario: $REPS"
echo "Verify mode: $VERIFY_FLAG"
echo "Dune jobs matrix: $DUNE_JOBS_RAW"
if [ "$COMPARE_STAGE0_POLICIES" = "1" ]; then
	echo "Stage0 policy mode: compare(wrapper=warn,native=prefer-native)"
else
	echo "Stage0 policy mode: ${STAGE0_POLICY:-default}"
fi
echo "Stage0 compile knobs: no_opt=$STAGE0_NO_OPT no_inline=$STAGE0_NO_INLINE disable_prepasses=$STAGE0_DISABLE_PREPASSES ocamlrunparam=${STAGE0_OCAMLRUNPARAM:-<unset>}"
if [ -n "$STAGE0_NATIVE_BIN" ]; then
	echo "Stage0 native candidate override: $STAGE0_NATIVE_BIN"
fi
echo "Reports: $REPORT_DIR"
echo ""

run_regen_with_policy() {
	local policy_value="$1"
	local dune_jobs="$2"
	local report_path="$3"
	shift 3
	local -a regen_args=("$@" "${verify_args[@]}")
	if [ -n "$report_path" ]; then
		regen_args+=(--report-json "$report_path")
	fi

	if [ -n "$policy_value" ] && [ -n "$STAGE0_NATIVE_BIN" ]; then
		HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY="$policy_value" \
		HXHX_STAGE0_NATIVE_HAXE_BIN="$STAGE0_NATIVE_BIN" \
		HXHX_DUNE_JOBS="$dune_jobs" \
		HXHX_STAGE0_NO_OPT="$STAGE0_NO_OPT" \
		HXHX_STAGE0_NO_INLINE="$STAGE0_NO_INLINE" \
		HXHX_STAGE0_DISABLE_PREPASSES="$STAGE0_DISABLE_PREPASSES" \
		HXHX_STAGE0_OCAMLRUNPARAM="$STAGE0_OCAMLRUNPARAM" \
		HAXE_BIN="$HAXE_BIN" \
		bash "$REGEN_SCRIPT" "${regen_args[@]}"
		return
	fi
	if [ -n "$policy_value" ]; then
		HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY="$policy_value" \
		HXHX_DUNE_JOBS="$dune_jobs" \
		HXHX_STAGE0_NO_OPT="$STAGE0_NO_OPT" \
		HXHX_STAGE0_NO_INLINE="$STAGE0_NO_INLINE" \
		HXHX_STAGE0_DISABLE_PREPASSES="$STAGE0_DISABLE_PREPASSES" \
		HXHX_STAGE0_OCAMLRUNPARAM="$STAGE0_OCAMLRUNPARAM" \
		HAXE_BIN="$HAXE_BIN" \
		bash "$REGEN_SCRIPT" "${regen_args[@]}"
		return
	fi
	if [ -n "$STAGE0_NATIVE_BIN" ]; then
		HXHX_STAGE0_NATIVE_HAXE_BIN="$STAGE0_NATIVE_BIN" \
		HXHX_DUNE_JOBS="$dune_jobs" \
		HXHX_STAGE0_NO_OPT="$STAGE0_NO_OPT" \
		HXHX_STAGE0_NO_INLINE="$STAGE0_NO_INLINE" \
		HXHX_STAGE0_DISABLE_PREPASSES="$STAGE0_DISABLE_PREPASSES" \
		HXHX_STAGE0_OCAMLRUNPARAM="$STAGE0_OCAMLRUNPARAM" \
		HAXE_BIN="$HAXE_BIN" \
		bash "$REGEN_SCRIPT" "${regen_args[@]}"
		return
	fi
	HXHX_DUNE_JOBS="$dune_jobs" \
	HXHX_STAGE0_NO_OPT="$STAGE0_NO_OPT" \
	HXHX_STAGE0_NO_INLINE="$STAGE0_NO_INLINE" \
	HXHX_STAGE0_DISABLE_PREPASSES="$STAGE0_DISABLE_PREPASSES" \
	HXHX_STAGE0_OCAMLRUNPARAM="$STAGE0_OCAMLRUNPARAM" \
	HAXE_BIN="$HAXE_BIN" \
	bash "$REGEN_SCRIPT" "${regen_args[@]}"
}

extract_report_metrics() {
	local report_path="$1"
	if ! command -v node >/dev/null 2>&1; then
		printf 'na\tna\tna\tna\tna\tna\tna\n'
		return
	fi
	node -e '
const fs = require("fs");
const reportPath = process.argv[1];
let report = {};
try {
  report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
} catch (_) {}
const get = (value) => (value === undefined || value === null || value === "" ? "na" : String(value));
const values = [
  get(report.phase_seconds && report.phase_seconds.emit),
  get(report.phase_seconds && report.phase_seconds.total),
  get(report.skipped_emit),
  get(report.haxe_bin_mode),
  get(report.haxe_bin_policy),
  get(report.haxe_bin_switched),
  get(report.stage0_observability && report.stage0_observability.heartbeat_peak_rss_mb)
];
process.stdout.write(values.join("\t"));
' "$report_path"
}

run_once() {
	local scenario="$1"
	local rep="$2"
	local policy_label="$3"
	local policy_value="$4"
	local dune_jobs="$5"
	shift 5
	local policy_slug="${policy_label//[^A-Za-z0-9._-]/_}"
	local dune_slug="${dune_jobs//[^A-Za-z0-9._-]/_}"
	local report_path="$REPORT_DIR/${scenario}.${policy_slug}.jobs${dune_slug}.run${rep}.json"
	local start_ts end_ts elapsed
	local emit_sec total_sec skipped_emit haxe_mode haxe_policy switched peak_rss_mb

	start_ts="$(date +%s)"
	run_regen_with_policy "$policy_value" "$dune_jobs" "$report_path" "$@"
	end_ts="$(date +%s)"
	elapsed="$((end_ts - start_ts))"

	IFS=$'\t' read -r emit_sec total_sec skipped_emit haxe_mode haxe_policy switched peak_rss_mb <<<"$(extract_report_metrics "$report_path")"

	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$scenario" "$policy_label" "$dune_jobs" "$rep" "$elapsed" "$emit_sec" "$total_sec" "$skipped_emit" "$haxe_mode" "$haxe_policy" "$switched" "$peak_rss_mb" "$report_path" >>"$RESULTS_TSV"
	printf 'run %-5s policy=%-14s jobs=%-5s #%s %4ss emit=%ss peak_rss=%sMB report=%s\n' \
		"$scenario" "$policy_label" "$dune_jobs" "$rep" "$elapsed" "$emit_sec" "$peak_rss_mb" "$report_path"
}

run_once_for_active_policies() {
	local scenario="$1"
	local rep="$2"
	shift 2
	local dune_jobs=""
	for dune_jobs in "${DUNE_JOBS_LIST[@]}"; do
		if [ "$COMPARE_STAGE0_POLICIES" = "1" ]; then
			run_once "$scenario" "$rep" "wrapper" "warn" "$dune_jobs" "$@"
			run_once "$scenario" "$rep" "native" "prefer-native" "$dune_jobs" "$@"
			continue
		fi
		local policy_label="default"
		if [ -n "$STAGE0_POLICY" ]; then
			policy_label="$STAGE0_POLICY"
		fi
		run_once "$scenario" "$rep" "$policy_label" "$STAGE0_POLICY" "$dune_jobs" "$@"
	done
}

run_scenario_cold() {
	local rep
	for rep in $(seq 1 "$REPS"); do
		bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true
		run_once_for_active_policies "cold" "$rep" --full --clean-out --force
	done
}

run_scenario_warm() {
	local rep
	for rep in $(seq 1 "$REPS"); do
		run_once_for_active_policies "warm" "$rep" --incremental --use-repo-server --keep-repo-server --force
	done
}

run_skip_for_policy() {
	local rep="$1"
	local policy_label="$2"
	local policy_value="$3"
	local dune_jobs="$4"
	echo "Priming fingerprint for skip scenario policy=$policy_label (not measured)..."
	run_regen_with_policy "$policy_value" "$dune_jobs" "" --incremental --use-repo-server --keep-repo-server --force --no-verify >/dev/null
	run_once "skip" "$rep" "$policy_label" "$policy_value" "$dune_jobs" --incremental --use-repo-server --keep-repo-server --skip-if-unchanged
}

run_scenario_skip() {
	local rep
	local dune_jobs
	for rep in $(seq 1 "$REPS"); do
		for dune_jobs in "${DUNE_JOBS_LIST[@]}"; do
			if [ "$COMPARE_STAGE0_POLICIES" = "1" ]; then
				run_skip_for_policy "$rep" "wrapper" "warn" "$dune_jobs"
				run_skip_for_policy "$rep" "native" "prefer-native" "$dune_jobs"
			else
				local policy_label="default"
				if [ -n "$STAGE0_POLICY" ]; then
					policy_label="$STAGE0_POLICY"
				fi
				run_skip_for_policy "$rep" "$policy_label" "$STAGE0_POLICY" "$dune_jobs"
			fi
		done
	done
}

run_scenario_select() {
	local rep
	for rep in $(seq 1 "$REPS"); do
		run_once_for_active_policies "select" "$rep" --stage0-selection-only
	done
}

IFS=',' read -r -a scenarios <<<"$SCENARIOS_RAW"
for scenario in "${scenarios[@]}"; do
	case "$scenario" in
		cold)
			echo "-- scenario=cold"
			run_scenario_cold
			;;
		warm)
			echo "-- scenario=warm"
			run_scenario_warm
			;;
		skip)
			echo "-- scenario=skip"
			run_scenario_skip
			;;
		select)
			echo "-- scenario=select"
			run_scenario_select
			;;
		'')
			;;
		*)
			echo "Unknown scenario '$scenario'. Allowed values: cold,warm,skip,select." >&2
			exit 1
			;;
	esac
done

echo ""
echo "== Summary (seconds)"
awk -F '\t' '
NR == 1 {
	next
}
{
	sc = $1
	policy = $2
	jobs = $3
	key = sc "|" policy "|" jobs
	sec = $5 + 0
	if (!(key in count)) {
		count[key] = 0
		sum[key] = 0
		best[key] = sec
		worst[key] = sec
		scenario[key] = sc
		policies[key] = policy
		dune_jobs[key] = jobs
	}
	count[key]++
	sum[key] += sec
	if (sec < best[key]) best[key] = sec
	if (sec > worst[key]) worst[key] = sec
}
END {
	printf "%-8s %-14s %-8s %-6s %-6s %-6s %-6s\n", "scenario", "policy", "jobs", "runs", "avg", "best", "worst"
	for (key in count) {
		avg = int(sum[key] / count[key])
		printf "%-8s %-14s %-8s %-6d %-6d %-6d %-6d\n", scenario[key], policies[key], dune_jobs[key], count[key], avg, best[key], worst[key]
	}
}
' "$RESULTS_TSV"

echo ""
echo "Detailed results: $RESULTS_TSV"

if git -C "$ROOT" diff --quiet --ignore-submodules -- \
	&& git -C "$ROOT" diff --cached --quiet --ignore-submodules --; then
	SOURCE_CLEAN_AT_END="true"
else
	SOURCE_CLEAN_AT_END="false"
fi

node "$REPORT_BUILDER" build \
	--results-tsv "$RESULTS_TSV" \
	--reports-dir "$REPORT_DIR" \
	--json-out "$REPORT_JSON" \
	--git-commit "$SOURCE_COMMIT" \
	--start-tracked-source-clean "$SOURCE_CLEAN_AT_START" \
	--end-tracked-source-clean "$SOURCE_CLEAN_AT_END" \
	--scenarios "$SCENARIOS_RAW" \
	--reps "$REPS" \
	--verify "$VERIFY_FLAG" \
	--dune-jobs "$DUNE_JOBS_RAW" \
	--compare-stage0-policies "$COMPARE_STAGE0_POLICIES" \
	--stage0-policy "$STAGE0_POLICY" \
	--stage0-native-bin "$STAGE0_NATIVE_BIN" \
	--stage0-no-opt "$STAGE0_NO_OPT" \
	--stage0-no-inline "$STAGE0_NO_INLINE" \
	--stage0-disable-prepasses "$STAGE0_DISABLE_PREPASSES" \
	--stage0-ocamlrunparam "$STAGE0_OCAMLRUNPARAM"
node "$REPORT_BUILDER" validate --report "$REPORT_JSON"
echo "Self-describing report: $REPORT_JSON"
