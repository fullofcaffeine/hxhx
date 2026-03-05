#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE_SCRIPT="$ROOT/scripts/hxhx/profile-stage0-regen.sh"

REPS="${HXHX_STAGE0_AB_REPS:-3}"
FAILFAST_SECS="${HXHX_STAGE0_AB_FAILFAST_SECS:-120}"
HEARTBEAT_SECS="${HXHX_STAGE0_AB_HEARTBEAT_SECS:-20}"
POLICY="${HXHX_STAGE0_AB_POLICY:-prefer-native}"
BASELINE_ARGS_RAW="${HXHX_STAGE0_AB_BASELINE_ARGS:-}"
MITIGATION_ARGS_RAW="${HXHX_STAGE0_AB_MITIGATION_ARGS:---disable-prepasses}"
OUT_DIR="${HXHX_STAGE0_AB_OUT_DIR:-$ROOT/.hxhx/profile/stage0-regen-ab/$(date +%Y%m%d-%H%M%S)}"

usage() {
	cat <<'USAGE'
Usage: bash scripts/hxhx/profile-stage0-regen-ab.sh [options]

Runs repeated A/B profiling for stage0 regen and summarizes peak RSS reduction
using median/average across repetitions.

Options:
  --reps <N>                    Number of A/B repetitions (default: 3)
  --failfast <seconds>          Failfast timeout for each run (default: 120)
  --heartbeat <seconds>         Heartbeat interval (default: 20)
  --policy <mode>               Stage0 policy (default: prefer-native)
  --baseline-args "<args>"      Extra args for baseline profile runs
  --mitigation-args "<args>"    Extra args for mitigation profile runs
                                (default: --disable-prepasses)
  --out-dir <dir>               Output directory
  -h, --help                    Show this help

Environment equivalents:
  HXHX_STAGE0_AB_REPS
  HXHX_STAGE0_AB_FAILFAST_SECS
  HXHX_STAGE0_AB_HEARTBEAT_SECS
  HXHX_STAGE0_AB_POLICY
  HXHX_STAGE0_AB_BASELINE_ARGS
  HXHX_STAGE0_AB_MITIGATION_ARGS
  HXHX_STAGE0_AB_OUT_DIR

Output files:
  <out-dir>/results.tsv
  <out-dir>/summary.txt
  <out-dir>/summary.json
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

while [ "$#" -gt 0 ]; do
	case "$1" in
		--reps)
			REPS="${2:-}"
			shift 2
			;;
		--failfast)
			FAILFAST_SECS="${2:-}"
			shift 2
			;;
		--heartbeat)
			HEARTBEAT_SECS="${2:-}"
			shift 2
			;;
		--policy)
			POLICY="${2:-}"
			shift 2
			;;
		--baseline-args)
			BASELINE_ARGS_RAW="${2:-}"
			shift 2
			;;
		--mitigation-args)
			MITIGATION_ARGS_RAW="${2:-}"
			shift 2
			;;
		--out-dir)
			OUT_DIR="${2:-}"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

if ! is_non_negative_int "$REPS" || [ "$REPS" = "0" ]; then
	echo "Invalid --reps: $REPS (expected positive integer)." >&2
	exit 2
fi
if ! is_non_negative_int "$FAILFAST_SECS"; then
	echo "Invalid --failfast: $FAILFAST_SECS (expected non-negative integer)." >&2
	exit 2
fi
if ! is_non_negative_int "$HEARTBEAT_SECS"; then
	echo "Invalid --heartbeat: $HEARTBEAT_SECS (expected non-negative integer)." >&2
	exit 2
fi
case "$POLICY" in
	warn|prefer-native|require-native)
		;;
	*)
		echo "Invalid --policy: $POLICY (expected warn|prefer-native|require-native)." >&2
		exit 2
		;;
esac

mkdir -p "$OUT_DIR"
RESULTS_TSV="$OUT_DIR/results.tsv"
SUMMARY_TXT="$OUT_DIR/summary.txt"
SUMMARY_JSON="$OUT_DIR/summary.json"

printf 'rep\tlane\tpeak_rss_mb\tpeak_rss_source\ttotal_sec\tstatus\texit_code\treport_json\n' >"$RESULTS_TSV"

echo "== Stage0 A/B profile"
echo "reps=$REPS failfast=${FAILFAST_SECS}s heartbeat=${HEARTBEAT_SECS}s policy=$POLICY"
echo "baseline_args=${BASELINE_ARGS_RAW:-<none>}"
echo "mitigation_args=${MITIGATION_ARGS_RAW:-<none>}"
echo "out_dir=$OUT_DIR"

run_lane() {
	local rep="$1"
	local lane="$2"
	local args_raw="$3"
	local run_dir="$OUT_DIR/${lane}-r${rep}"
	local -a lane_args=()
	local report_json=""
	local summary_file=""
	local peak_source="report"
	local peak_rss=""
	local total_sec=""
	local status=""
	local exit_code=""

	if [ -n "$args_raw" ]; then
		# shellcheck disable=SC2206
		lane_args=( $args_raw )
	fi

	echo "== rep=$rep lane=$lane"
	if [ "${#lane_args[@]}" -gt 0 ]; then
		bash "$PROFILE_SCRIPT" \
			--policy "$POLICY" \
			--failfast "$FAILFAST_SECS" \
			--heartbeat "$HEARTBEAT_SECS" \
			--out-dir "$run_dir" \
			"${lane_args[@]}"
	else
		bash "$PROFILE_SCRIPT" \
			--policy "$POLICY" \
			--failfast "$FAILFAST_SECS" \
			--heartbeat "$HEARTBEAT_SECS" \
			--out-dir "$run_dir"
	fi

	report_json="$run_dir/regen_report.json"
	summary_file="$run_dir/summary.txt"
	if [ -f "$summary_file" ]; then
		peak_source="$(sed -n 's/.*peak_rss_source=\([^ ]*\).*/\1/p' "$summary_file" | head -n 1)"
		if [ -z "$peak_source" ]; then
			peak_source="report"
		fi
	fi
	peak_rss="$(jq -r '.stage0_observability.heartbeat_peak_rss_mb // "na"' "$report_json")"
	total_sec="$(jq -r '.phase_seconds.total // "na"' "$report_json")"
	status="$(jq -r '.status // "na"' "$report_json")"
	exit_code="$(jq -r '.exit_code // "na"' "$report_json")"

	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$rep" "$lane" "$peak_rss" "$peak_source" "$total_sec" "$status" "$exit_code" "$report_json" >>"$RESULTS_TSV"
}

rep=""
for rep in $(seq 1 "$REPS"); do
	run_lane "$rep" "baseline" "$BASELINE_ARGS_RAW"
	run_lane "$rep" "mitigation" "$MITIGATION_ARGS_RAW"
done

node -e '
const fs = require("fs");
const tsvPath = process.argv[1];
const summaryJsonPath = process.argv[2];
const lines = fs.readFileSync(tsvPath, "utf8").trim().split(/\n/);
const rows = lines.slice(1).map((line) => {
  const [rep, lane, peak, peakSource, totalSec, status, exitCode, reportJson] = line.split("\t");
  return { rep: Number(rep), lane, peak: Number(peak), peakSource, totalSec: Number(totalSec), status, exitCode, reportJson };
});
const pick = (lane) => rows.filter((r) => r.lane === lane && Number.isFinite(r.peak) && r.peak > 0);
const baseline = pick("baseline");
const mitigation = pick("mitigation");
const avg = (arr) => arr.length === 0 ? null : arr.reduce((a, b) => a + b, 0) / arr.length;
const median = (arr) => {
  if (arr.length === 0) return null;
  const s = [...arr].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 === 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid];
};
const bPeaks = baseline.map((r) => r.peak);
const mPeaks = mitigation.map((r) => r.peak);
const bAvg = avg(bPeaks);
const mAvg = avg(mPeaks);
const bMedian = median(bPeaks);
const mMedian = median(mPeaks);
const hasAvg = bAvg !== null && mAvg !== null && bAvg > 0;
const hasMedian = bMedian !== null && mMedian !== null && bMedian > 0;
const avgReductionPct = hasAvg ? ((bAvg - mAvg) / bAvg) * 100 : null;
const medianReductionPct = hasMedian ? ((bMedian - mMedian) / bMedian) * 100 : null;
const out = {
  schema: "stage0-profile-ab-summary.v1",
  runs: rows.length,
  baseline_runs: baseline.length,
  mitigation_runs: mitigation.length,
  baseline_avg_peak_rss_mb: bAvg,
  mitigation_avg_peak_rss_mb: mAvg,
  baseline_median_peak_rss_mb: bMedian,
  mitigation_median_peak_rss_mb: mMedian,
  avg_reduction_pct: avgReductionPct,
  median_reduction_pct: medianReductionPct
};
fs.writeFileSync(summaryJsonPath, JSON.stringify(out, null, 2));
const fmt = (v, d = 2) => v === null || v === undefined ? "na" : Number(v).toFixed(d);
console.log(`baseline_avg_peak_rss_mb=${fmt(bAvg, 0)}`);
console.log(`mitigation_avg_peak_rss_mb=${fmt(mAvg, 0)}`);
console.log(`baseline_median_peak_rss_mb=${fmt(bMedian, 0)}`);
console.log(`mitigation_median_peak_rss_mb=${fmt(mMedian, 0)}`);
console.log(`avg_reduction_pct=${fmt(avgReductionPct)}`);
console.log(`median_reduction_pct=${fmt(medianReductionPct)}`);
' "$RESULTS_TSV" "$SUMMARY_JSON" | tee "$SUMMARY_TXT"

echo "results_tsv=$RESULTS_TSV" | tee -a "$SUMMARY_TXT"
echo "summary_json=$SUMMARY_JSON" | tee -a "$SUMMARY_TXT"
