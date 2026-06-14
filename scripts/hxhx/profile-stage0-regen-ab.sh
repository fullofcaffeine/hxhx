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
MIN_REDUCTION_PCT="${HXHX_STAGE0_AB_MIN_REDUCTION_PCT:-}"
REDUCTION_METRIC="${HXHX_STAGE0_AB_REDUCTION_METRIC:-median}"
REQUIRE_STATUS_PARITY="${HXHX_STAGE0_AB_REQUIRE_STATUS_PARITY:-0}"
PARITY_MODE="${HXHX_STAGE0_AB_PARITY_MODE:-status-exit}"
CONTRACT_ROLE="diagnostic-only"

usage() {
	cat <<'USAGE'
Usage: bash scripts/hxhx/profile-stage0-regen-ab.sh [options]

Runs repeated A/B profiling for stage0 regen and summarizes peak RSS reduction
using median/average across repetitions.

This runner is diagnostic-only. Its output may guide source-build tuning, but it
is not Full 1.0 release proof and must not be used as Haxe parity evidence.

Options:
  --reps <N>                    Number of A/B repetitions (default: 3)
  --failfast <seconds>          Failfast timeout for each run (default: 120)
  --heartbeat <seconds>         Heartbeat interval (default: 20)
  --policy <mode>               Stage0 policy (default: prefer-native)
  --baseline-args "<args>"      Extra args for baseline profile runs
  --mitigation-args "<args>"    Extra args for mitigation profile runs
                                (default: --disable-prepasses)
  --min-reduction-pct <pct>     Optional threshold gate (e.g. 20)
  --reduction-metric <name>     Which reduction metric to gate on: median|avg
                                (default: median)
  --require-status-parity       Require baseline/mitigation per-rep parity (fails on mismatch)
  --allow-status-mismatch       Disable parity gate (default behavior)
  --parity-mode <name>          Parity check mode: status|status-exit
                                (default: status-exit)
  --out-dir <dir>               Output directory
  -h, --help                    Show this help

Environment equivalents:
  HXHX_STAGE0_AB_REPS
  HXHX_STAGE0_AB_FAILFAST_SECS
  HXHX_STAGE0_AB_HEARTBEAT_SECS
  HXHX_STAGE0_AB_POLICY
  HXHX_STAGE0_AB_BASELINE_ARGS
  HXHX_STAGE0_AB_MITIGATION_ARGS
  HXHX_STAGE0_AB_MIN_REDUCTION_PCT
  HXHX_STAGE0_AB_REDUCTION_METRIC
  HXHX_STAGE0_AB_REQUIRE_STATUS_PARITY
  HXHX_STAGE0_AB_PARITY_MODE
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

assert_bool_01() {
	case "$2" in
		0|1)
			;;
		*)
			echo "Invalid $1: $2 (expected 0 or 1)." >&2
			exit 2
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
		--min-reduction-pct)
			MIN_REDUCTION_PCT="${2:-}"
			shift 2
			;;
		--reduction-metric)
			REDUCTION_METRIC="${2:-}"
			shift 2
			;;
		--require-status-parity)
			REQUIRE_STATUS_PARITY=1
			shift
			;;
		--allow-status-mismatch)
			REQUIRE_STATUS_PARITY=0
			shift
			;;
		--parity-mode)
			PARITY_MODE="${2:-}"
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
case "$REDUCTION_METRIC" in
	median|avg)
		;;
	*)
		echo "Invalid --reduction-metric: $REDUCTION_METRIC (expected median|avg)." >&2
		exit 2
		;;
esac
case "$PARITY_MODE" in
	status|status-exit)
		;;
	*)
		echo "Invalid --parity-mode: $PARITY_MODE (expected status|status-exit)." >&2
		exit 2
		;;
esac
assert_bool_01 "REQUIRE_STATUS_PARITY" "$REQUIRE_STATUS_PARITY"
if [ -n "$MIN_REDUCTION_PCT" ]; then
	if ! [[ "$MIN_REDUCTION_PCT" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
		echo "Invalid --min-reduction-pct: $MIN_REDUCTION_PCT (expected non-negative number)." >&2
		exit 2
	fi
fi

mkdir -p "$OUT_DIR"
RESULTS_TSV="$OUT_DIR/results.tsv"
SUMMARY_TXT="$OUT_DIR/summary.txt"
SUMMARY_JSON="$OUT_DIR/summary.json"

printf 'rep\tlane\tpeak_rss_mb\tpeak_rss_source\ttotal_sec\tstatus\texit_code\treport_json\n' >"$RESULTS_TSV"

echo "== Stage0 A/B profile"
echo "reps=$REPS failfast=${FAILFAST_SECS}s heartbeat=${HEARTBEAT_SECS}s policy=$POLICY"
echo "baseline_args=${BASELINE_ARGS_RAW:-<none>}"
echo "mitigation_args=${MITIGATION_ARGS_RAW:-<none>}"
echo "min_reduction_pct=${MIN_REDUCTION_PCT:-<none>} reduction_metric=$REDUCTION_METRIC"
echo "require_status_parity=$REQUIRE_STATUS_PARITY parity_mode=$PARITY_MODE"
echo "contract_role=$CONTRACT_ROLE release_evidence=false"
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
const parityMode = process.argv[3];
const contractRole = process.argv[4];
const lines = fs.readFileSync(tsvPath, "utf8").trim().split(/\n/);
const rows = lines.slice(1).map((line) => {
  const [rep, lane, peak, peakSource, totalSec, status, exitCode, reportJson] = line.split("\t");
  return {
    rep: Number(rep),
    lane,
    peak: Number(peak),
    peakSource,
    totalSec: Number(totalSec),
    status,
    exitCode: String(exitCode),
    reportJson
  };
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
const countByStatus = (arr) => arr.reduce((acc, row) => {
  const key = row.status || "na";
  acc[key] = (acc[key] || 0) + 1;
  return acc;
}, {});
const pairMap = new Map();
for (const row of rows) {
  const rep = row.rep;
  if (!pairMap.has(rep)) {
    pairMap.set(rep, { rep, baseline: null, mitigation: null });
  }
  const entry = pairMap.get(rep);
  if (row.lane === "baseline") {
    entry.baseline = row;
  } else if (row.lane === "mitigation") {
    entry.mitigation = row;
  }
}
const pairs = [...pairMap.values()].filter((entry) => entry.baseline !== null && entry.mitigation !== null);
const pairSummary = pairs.map((entry) => {
  const b = entry.baseline;
  const m = entry.mitigation;
  const statusMatch = b.status === m.status;
  const statusExitMatch = statusMatch && b.exitCode === m.exitCode;
  const equivalent = parityMode === "status" ? statusMatch : statusExitMatch;
  const successPair = b.status === "ok" && m.status === "ok";
  return { rep: entry.rep, statusMatch, statusExitMatch, equivalent, successPair };
});
const pairedRuns = pairSummary.length;
const statusMatchPairs = pairSummary.filter((p) => p.statusMatch).length;
const statusExitMatchPairs = pairSummary.filter((p) => p.statusExitMatch).length;
const equivalentPairs = pairSummary.filter((p) => p.equivalent).length;
const allEquivalent = pairedRuns > 0 && equivalentPairs === pairedRuns;
const allSuccess = pairedRuns > 0 && pairSummary.every((p) => p.successPair);
const allFailMode = pairedRuns > 0 && pairSummary.every((p) => !p.successPair);
let parityClassification = "insufficient-data";
if (pairedRuns > 0) {
  if (!allEquivalent) {
    parityClassification = "non-equivalent";
  } else if (allSuccess) {
    parityClassification = "equivalent-success";
  } else if (allFailMode) {
    parityClassification = "equivalent-fail-mode";
  } else {
    parityClassification = "equivalent-mixed";
  }
}
let recommendation = "profiling-only";
if (parityClassification === "non-equivalent" || parityClassification === "insufficient-data") {
  recommendation = "profiling-only";
} else if ((avgReductionPct !== null && avgReductionPct < 0) && (medianReductionPct !== null && medianReductionPct < 0)) {
  recommendation = "rejected";
} else if (medianReductionPct !== null && medianReductionPct >= 20) {
  recommendation = "promotable";
} else {
  recommendation = "profiling-only";
}
const out = {
  schema: "stage0-profile-ab-summary.v1",
  contract_role: contractRole,
  release_evidence: false,
  proof_scope: "maintenance-source-build-diagnostic",
  proof_note: "Stage0 source-build A/B profiling is observability evidence only; it is not Haxe 4.3.7 parity or Full 1.0 release proof.",
  runs: rows.length,
  baseline_runs: baseline.length,
  mitigation_runs: mitigation.length,
  baseline_avg_peak_rss_mb: bAvg,
  mitigation_avg_peak_rss_mb: mAvg,
  baseline_median_peak_rss_mb: bMedian,
  mitigation_median_peak_rss_mb: mMedian,
  avg_reduction_pct: avgReductionPct,
  median_reduction_pct: medianReductionPct,
  parity_mode: parityMode,
  paired_runs: pairedRuns,
  status_match_pairs: statusMatchPairs,
  status_exit_match_pairs: statusExitMatchPairs,
  equivalent_pairs: equivalentPairs,
  baseline_status_counts: countByStatus(baseline),
  mitigation_status_counts: countByStatus(mitigation),
  parity_classification: parityClassification,
  recommendation
};
fs.writeFileSync(summaryJsonPath, JSON.stringify(out, null, 2));
const fmt = (v, d = 2) => v === null || v === undefined ? "na" : Number(v).toFixed(d);
console.log(`baseline_avg_peak_rss_mb=${fmt(bAvg, 0)}`);
console.log(`mitigation_avg_peak_rss_mb=${fmt(mAvg, 0)}`);
console.log(`baseline_median_peak_rss_mb=${fmt(bMedian, 0)}`);
console.log(`mitigation_median_peak_rss_mb=${fmt(mMedian, 0)}`);
console.log(`avg_reduction_pct=${fmt(avgReductionPct)}`);
console.log(`median_reduction_pct=${fmt(medianReductionPct)}`);
console.log(`parity_mode=${parityMode}`);
console.log(`paired_runs=${pairedRuns}`);
console.log(`equivalent_pairs=${equivalentPairs}`);
console.log(`parity_classification=${parityClassification}`);
console.log(`recommendation=${recommendation}`);
console.log(`contract_role=${contractRole}`);
console.log("release_evidence=false");
' "$RESULTS_TSV" "$SUMMARY_JSON" "$PARITY_MODE" "$CONTRACT_ROLE" | tee "$SUMMARY_TXT"

if [ "$REQUIRE_STATUS_PARITY" = "1" ]; then
	paired_runs="$(jq -r '.paired_runs // 0' "$SUMMARY_JSON")"
	equivalent_pairs="$(jq -r '.equivalent_pairs // 0' "$SUMMARY_JSON")"
	parity_classification="$(jq -r '.parity_classification // "insufficient-data"' "$SUMMARY_JSON")"
	if [ "$paired_runs" = "0" ]; then
		echo "parity_gate_status=fail reason=no_paired_runs parity_mode=$PARITY_MODE" | tee -a "$SUMMARY_TXT"
		exit 4
	fi
	if [ "$equivalent_pairs" != "$paired_runs" ]; then
		echo "parity_gate_status=fail reason=non_equivalent_pairs parity_mode=$PARITY_MODE paired_runs=$paired_runs equivalent_pairs=$equivalent_pairs classification=$parity_classification" | tee -a "$SUMMARY_TXT"
		exit 4
	fi
	echo "parity_gate_status=pass parity_mode=$PARITY_MODE paired_runs=$paired_runs equivalent_pairs=$equivalent_pairs classification=$parity_classification" | tee -a "$SUMMARY_TXT"
fi

if [ -n "$MIN_REDUCTION_PCT" ]; then
	gate_value="$(jq -r "if \"$REDUCTION_METRIC\" == \"avg\" then .avg_reduction_pct else .median_reduction_pct end" "$SUMMARY_JSON")"
	if [ "$gate_value" = "null" ] || [ -z "$gate_value" ]; then
		echo "gate_status=fail reason=no_${REDUCTION_METRIC}_reduction_value threshold_pct=$MIN_REDUCTION_PCT" | tee -a "$SUMMARY_TXT"
		exit 3
	fi
	if awk -v value="$gate_value" -v threshold="$MIN_REDUCTION_PCT" 'BEGIN { exit(value + 0 >= threshold + 0 ? 0 : 1) }'; then
		echo "gate_status=pass metric=$REDUCTION_METRIC value_pct=$gate_value threshold_pct=$MIN_REDUCTION_PCT" | tee -a "$SUMMARY_TXT"
	else
		echo "gate_status=fail metric=$REDUCTION_METRIC value_pct=$gate_value threshold_pct=$MIN_REDUCTION_PCT" | tee -a "$SUMMARY_TXT"
		exit 3
	fi
fi

echo "results_tsv=$RESULTS_TSV" | tee -a "$SUMMARY_TXT"
echo "summary_json=$SUMMARY_JSON" | tee -a "$SUMMARY_TXT"
