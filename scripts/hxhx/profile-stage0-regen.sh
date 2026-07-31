#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGEN_SCRIPT="${HXHX_STAGE0_PROFILE_REGEN_SCRIPT:-$ROOT/scripts/hxhx/regenerate-hxhx-bootstrap.sh}"
PROGRESS_SUMMARY_SCRIPT="$ROOT/scripts/hxhx/summarize-stage0-progress.js"
HEARTBEAT_SUMMARY_SCRIPT="$ROOT/scripts/hxhx/summarize-stage0-heartbeat-trace.js"
CAPACITY_SCRIPT="$ROOT/scripts/hxhx/check-local-capacity.js"
CAPACITY_LEASE_OWNER_PID="${HXHX_HEAVY_RUN_LEASE_OWNER_PID:-$$}"
CAPACITY_LEASE_PRIMARY_OWNER=0
CAPACITY_LEASE_ACTIVE=0
if [ -z "${HXHX_HEAVY_RUN_LEASE_OWNER_PID:-}" ]; then
	CAPACITY_LEASE_PRIMARY_OWNER=1
	export HXHX_HEAVY_RUN_LEASE_OWNER_PID="$CAPACITY_LEASE_OWNER_PID"
fi

release_capacity_lease() {
	if [ "$CAPACITY_LEASE_PRIMARY_OWNER" = "1" ] && [ "$CAPACITY_LEASE_ACTIVE" = "1" ]; then
		node "$CAPACITY_SCRIPT" \
			--release-lease \
			--lease-owner-pid "$CAPACITY_LEASE_OWNER_PID" >/dev/null 2>&1 || true
	fi
}
trap release_capacity_lease EXIT

POLICY="${HXHX_STAGE0_PROFILE_POLICY:-prefer-native}"
FAILFAST_SECS="${HXHX_STAGE0_PROFILE_FAILFAST_SECS:-120}"
HEARTBEAT_SECS="${HXHX_STAGE0_PROFILE_HEARTBEAT_SECS:-20}"
NO_OPT="${HXHX_STAGE0_PROFILE_NO_OPT:-0}"
NO_INLINE="${HXHX_STAGE0_PROFILE_NO_INLINE:-0}"
STAGE0_NO_EXPR_MACROS="${HXHX_STAGE0_PROFILE_NO_EXPR_MACROS:-0}"
STAGE0_NO_EXTERNAL_MACRO_HOST="${HXHX_STAGE0_PROFILE_NO_EXTERNAL_MACRO_HOST:-0}"
STAGE0_NO_STAGE3="${HXHX_STAGE0_PROFILE_NO_STAGE3:-0}"
STAGE0_NO_INTERNAL_TOOLS="${HXHX_STAGE0_PROFILE_NO_INTERNAL_TOOLS:-0}"
STAGE0_NO_DISPLAY="${HXHX_STAGE0_PROFILE_NO_DISPLAY:-0}"
DISABLE_PREPASSES="${HXHX_STAGE0_PROFILE_DISABLE_PREPASSES:-0}"
STAGE0_OCAML_ONLY="${HXHX_STAGE0_PROFILE_OCAML_ONLY:-0}"
STAGE0_NO_LINE_DIRECTIVES="${HXHX_STAGE0_PROFILE_NO_LINE_DIRECTIVES:-0}"
STAGE0_OCAMLRUNPARAM="${HXHX_STAGE0_PROFILE_OCAMLRUNPARAM:-}"
SCENARIO_ARGS="${HXHX_STAGE0_PROFILE_SCENARIO_ARGS:---incremental --no-verify --force}"
TELEMETRY_DETAIL="${HXHX_STAGE0_PROFILE_TELEMETRY_DETAIL:-0}"
TELEMETRY_CLASS="${HXHX_STAGE0_PROFILE_TELEMETRY_CLASS:-}"
OUT_DIR="${HXHX_STAGE0_PROFILE_OUT_DIR:-$ROOT/.hxhx/profile/stage0-regen/$(date +%Y%m%d-%H%M%S)}"
CAPACITY_POLICY="${HXHX_STAGE0_PROFILE_CAPACITY_POLICY:-${HXHX_HEAVY_RUN_CAPACITY_POLICY:-auto}}"
CAPACITY_MAX_LOAD_PER_CPU="${HXHX_STAGE0_PROFILE_CAPACITY_MAX_LOAD_PER_CPU:-${HXHX_HEAVY_RUN_MAX_LOAD_PER_CPU:-}}"
# Deterministic host input for the repository fixture; ordinary runs inspect
# the real host and never need to set this.
CAPACITY_FIXTURE="${HXHX_STAGE0_PROFILE_CAPACITY_FIXTURE:-}"

usage() {
	cat <<'USAGE'
Usage: bash scripts/hxhx/profile-stage0-regen.sh [options]

Runs `regenerate-hxhx-bootstrap.sh` in telemetry mode and summarizes top contributors
from `reflaxe_ocaml_progress` logs + regen report JSON.

Options:
  --policy <warn|prefer-native|require-native>   Stage0 haxe policy (default: prefer-native)
  --failfast <seconds>                           Stage0 failfast timeout (default: 120)
  --heartbeat <seconds>                          Stage0 heartbeat seconds (default: 20)
  --no-opt                                       Enable stage0 --no-opt mitigation
  --no-inline                                    Enable stage0 --no-inline mitigation
  --no-expr-macros                               Trim Stage3 expression macro expander path in stage0 compile graph
  --no-external-macro-host                       Trim external macro-host runtime paths in stage0 compile graph
  --no-stage3                                    Trim Stage3 native lane paths in stage0 compile graph
  --no-internal-tools                            Trim internal bring-up CLI paths in stage0 compile graph
  --no-display                                   Trim Stage3 display synthesis paths in stage0 compile graph
  --disable-prepasses                            Enable stage0 prepass disable define
  --ocaml-only                                   Enable stage0 ocaml-only backend graph define
  --no-line-directives                           Disable OCaml line directives during stage0 emit
  --ocamlrunparam <value>                        Set OCAMLRUNPARAM for stage0 haxe process
  --telemetry-detail                             Enable detailed builder telemetry
  --telemetry-class <TypeName>                   Restrict detail telemetry to one class
  --scenario-args "<args>"                       Regen args string (default: --incremental --no-verify --force)
  --capacity-policy <auto|require|warn|off>      Stop or annotate saturated-host runs (default: auto)
  --capacity-max-load-per-cpu <number>           Override the normalized sustained-load limit
  --out-dir <dir>                                Output directory for artifacts/summary
  -h, --help                                     Show this help

Outputs:
  <out-dir>/capacity_report.json
  <out-dir>/regen_report.json
  <out-dir>/reflaxe_ocaml_progress.log
  <out-dir>/stage0_heartbeat_trace.jsonl
  <out-dir>/heartbeat_summary.json
  <out-dir>/summary.txt
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
		--policy)
			POLICY="${2:-}"
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
		--no-inline)
			NO_INLINE=1
			shift
			;;
		--no-expr-macros)
			STAGE0_NO_EXPR_MACROS=1
			shift
			;;
		--no-external-macro-host)
			STAGE0_NO_EXTERNAL_MACRO_HOST=1
			shift
			;;
		--no-stage3)
			STAGE0_NO_STAGE3=1
			shift
			;;
		--no-internal-tools)
			STAGE0_NO_INTERNAL_TOOLS=1
			shift
			;;
		--no-display)
			STAGE0_NO_DISPLAY=1
			shift
			;;
		--no-opt)
			NO_OPT=1
			shift
			;;
		--disable-prepasses)
			DISABLE_PREPASSES=1
			shift
			;;
		--ocaml-only)
			STAGE0_OCAML_ONLY=1
			shift
			;;
		--no-line-directives)
			STAGE0_NO_LINE_DIRECTIVES=1
			shift
			;;
		--ocamlrunparam)
			shift
			if [ "$#" -eq 0 ]; then
				echo "Missing value for --ocamlrunparam" >&2
				exit 2
			fi
			STAGE0_OCAMLRUNPARAM="$1"
			shift
			;;
		--telemetry-detail)
			TELEMETRY_DETAIL=1
			shift
			;;
		--telemetry-class)
			TELEMETRY_CLASS="${2:-}"
			shift 2
			;;
		--scenario-args)
			SCENARIO_ARGS="${2:-}"
			shift 2
			;;
		--capacity-policy)
			CAPACITY_POLICY="${2:-}"
			shift 2
			;;
		--capacity-max-load-per-cpu)
			CAPACITY_MAX_LOAD_PER_CPU="${2:-}"
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

case "$POLICY" in
	warn|prefer-native|require-native)
		;;
	*)
		echo "Invalid --policy: $POLICY (expected warn|prefer-native|require-native)." >&2
		exit 2
		;;
esac

case "$CAPACITY_POLICY" in
	auto|require|warn|off)
		;;
	*)
		echo "Invalid --capacity-policy: $CAPACITY_POLICY (expected auto|require|warn|off)." >&2
		exit 2
		;;
esac

if ! is_non_negative_int "$FAILFAST_SECS"; then
	echo "Invalid --failfast: $FAILFAST_SECS (expected non-negative integer)." >&2
	exit 2
fi
if ! is_non_negative_int "$HEARTBEAT_SECS"; then
	echo "Invalid --heartbeat: $HEARTBEAT_SECS (expected non-negative integer)." >&2
	exit 2
fi
assert_bool_01 "NO_OPT" "$NO_OPT"
assert_bool_01 "NO_INLINE" "$NO_INLINE"
assert_bool_01 "STAGE0_NO_EXPR_MACROS" "$STAGE0_NO_EXPR_MACROS"
assert_bool_01 "STAGE0_NO_EXTERNAL_MACRO_HOST" "$STAGE0_NO_EXTERNAL_MACRO_HOST"
assert_bool_01 "STAGE0_NO_STAGE3" "$STAGE0_NO_STAGE3"
assert_bool_01 "STAGE0_NO_INTERNAL_TOOLS" "$STAGE0_NO_INTERNAL_TOOLS"
assert_bool_01 "STAGE0_NO_DISPLAY" "$STAGE0_NO_DISPLAY"
assert_bool_01 "DISABLE_PREPASSES" "$DISABLE_PREPASSES"
assert_bool_01 "STAGE0_OCAML_ONLY" "$STAGE0_OCAML_ONLY"
assert_bool_01 "STAGE0_NO_LINE_DIRECTIVES" "$STAGE0_NO_LINE_DIRECTIVES"
assert_bool_01 "TELEMETRY_DETAIL" "$TELEMETRY_DETAIL"

if [ ! -x "$REGEN_SCRIPT" ]; then
	echo "Missing regen script: $REGEN_SCRIPT" >&2
	exit 2
fi

if [ -z "$OUT_DIR" ]; then
	echo "Invalid --out-dir: expected a non-empty path." >&2
	exit 2
fi

# The regeneration driver changes directories internally. Resolve the artifact
# root once so every child process writes to the caller-visible location.
case "$OUT_DIR" in
	/*) ;;
	*) OUT_DIR="$PWD/$OUT_DIR" ;;
esac
mkdir -p -- "$OUT_DIR"
OUT_DIR="$(cd -- "$OUT_DIR" && pwd -P)"
REPORT_JSON="$OUT_DIR/regen_report.json"
PROGRESS_LOG="$OUT_DIR/reflaxe_ocaml_progress.log"
HEARTBEAT_TRACE="$OUT_DIR/stage0_heartbeat_trace.jsonl"
SUMMARY_FILE="$OUT_DIR/summary.txt"
PROGRESS_SUMMARY_JSON="$OUT_DIR/progress_summary.json"
HEARTBEAT_SUMMARY_JSON="$OUT_DIR/heartbeat_summary.json"
RUN_STDOUT="$OUT_DIR/run.stdout.log"
RUN_STDERR="$OUT_DIR/run.stderr.log"
CAPACITY_REPORT="$OUT_DIR/capacity_report.json"

run_capacity_preflight() {
	if ! command -v node >/dev/null 2>&1; then
		echo "Missing node on PATH (required for the stage0 profile capacity preflight)." >&2
		exit 2
	fi
	if [ ! -f "$CAPACITY_SCRIPT" ]; then
		echo "Missing stage0 profile capacity helper: $CAPACITY_SCRIPT" >&2
		exit 2
	fi
	local -a args=(
		--policy "$CAPACITY_POLICY"
		--label "stage0-regeneration-profile"
		--lease-owner-pid "$CAPACITY_LEASE_OWNER_PID"
		--json-out "$CAPACITY_REPORT"
	)
	if [ -n "$CAPACITY_MAX_LOAD_PER_CPU" ]; then
		args+=(--max-load-per-cpu "$CAPACITY_MAX_LOAD_PER_CPU")
	fi
	if [ -n "$CAPACITY_FIXTURE" ]; then
		args+=(--fixture "$CAPACITY_FIXTURE")
	fi
	node "$CAPACITY_SCRIPT" "${args[@]}"
	if [ "${HXHX_HEAVY_RUN_WAIT_SECONDS:-0}" != "0" ]; then
		CAPACITY_LEASE_ACTIVE=1
	fi
}

# Capacity is checked before regeneration starts, so an overloaded workstation
# returns a retryable answer without spending minutes on invalid timing data.
run_capacity_preflight

echo "== Stage0 regen profile run"
echo "policy=$POLICY failfast=${FAILFAST_SECS}s heartbeat=${HEARTBEAT_SECS}s no_opt=$NO_OPT no_inline=$NO_INLINE no_expr_macros=$STAGE0_NO_EXPR_MACROS no_external_macro_host=$STAGE0_NO_EXTERNAL_MACRO_HOST no_stage3=$STAGE0_NO_STAGE3 no_internal_tools=$STAGE0_NO_INTERNAL_TOOLS no_display=$STAGE0_NO_DISPLAY disable_prepasses=$DISABLE_PREPASSES ocaml_only=$STAGE0_OCAML_ONLY no_line_directives=$STAGE0_NO_LINE_DIRECTIVES ocamlrunparam=${STAGE0_OCAMLRUNPARAM:-<unset>} telemetry_detail=$TELEMETRY_DETAIL"
echo "out_dir=$OUT_DIR"

set +e
REFLAXE_OCAML_PROGRESS_FILE="$PROGRESS_LOG" \
HXHX_STAGE0_HEARTBEAT_TRACE_FILE="$HEARTBEAT_TRACE" \
HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY="$POLICY" \
HXHX_STAGE0_FAILFAST_SECS="$FAILFAST_SECS" \
HXHX_STAGE0_HEARTBEAT="$HEARTBEAT_SECS" \
HXHX_STAGE0_TELEMETRY=1 \
HXHX_STAGE0_TELEMETRY_DETAIL="$TELEMETRY_DETAIL" \
HXHX_STAGE0_TELEMETRY_CLASS="$TELEMETRY_CLASS" \
HXHX_STAGE0_NO_OPT="$NO_OPT" \
HXHX_STAGE0_NO_INLINE="$NO_INLINE" \
HXHX_STAGE0_NO_EXPR_MACROS="$STAGE0_NO_EXPR_MACROS" \
HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST="$STAGE0_NO_EXTERNAL_MACRO_HOST" \
HXHX_STAGE0_NO_STAGE3="$STAGE0_NO_STAGE3" \
HXHX_STAGE0_NO_INTERNAL_TOOLS="$STAGE0_NO_INTERNAL_TOOLS" \
HXHX_STAGE0_NO_DISPLAY="$STAGE0_NO_DISPLAY" \
HXHX_STAGE0_DISABLE_PREPASSES="$DISABLE_PREPASSES" \
HXHX_STAGE0_OCAML_ONLY="$STAGE0_OCAML_ONLY" \
HXHX_STAGE0_NO_LINE_DIRECTIVES="$STAGE0_NO_LINE_DIRECTIVES" \
HXHX_STAGE0_OCAMLRUNPARAM="$STAGE0_OCAMLRUNPARAM" \
bash "$REGEN_SCRIPT" $SCENARIO_ARGS --report-json "$REPORT_JSON" >"$RUN_STDOUT" 2>"$RUN_STDERR"
run_code="$?"
set -e

node -e '
const fs = require("fs");
const reportPath = process.argv[1];
const runStdoutPath = process.argv[2];
let data = {};
try {
  data = JSON.parse(fs.readFileSync(reportPath, "utf8"));
} catch (_) {}
const extractPeakFromStdout = (stdoutPath) => {
  try {
    const text = fs.readFileSync(stdoutPath, "utf8");
    const matches = [...text.matchAll(/rss=(\d+)MB/g)];
    if (matches.length === 0) {
      return null;
    }
    let max = 0;
    for (const m of matches) {
      const value = Number(m[1]);
      if (Number.isFinite(value) && value > max) {
        max = value;
      }
    }
    return max > 0 ? max : null;
  } catch (_) {
    return null;
  }
};
const extractTreePeakFromStdout = (stdoutPath) => {
  try {
    const text = fs.readFileSync(stdoutPath, "utf8");
    const matches = [...text.matchAll(/tree_rss=(\d+)MB/g)];
    if (matches.length === 0) {
      return null;
    }
    let max = 0;
    for (const m of matches) {
      const value = Number(m[1]);
      if (Number.isFinite(value) && value > max) {
        max = value;
      }
    }
    return max > 0 ? max : null;
  } catch (_) {
    return null;
  }
};
const phase = data.phase_seconds || {};
const obs = data.stage0_observability || {};
const fallbackPeak = extractPeakFromStdout(runStdoutPath);
const fallbackTreePeak = extractTreePeakFromStdout(runStdoutPath);
const reportPeak = obs.heartbeat_peak_rss_mb;
const reportTreePeak = obs.heartbeat_peak_tree_rss_mb;
const peak = (reportPeak === undefined || reportPeak === null || Number(reportPeak) === 0) && fallbackPeak !== null
  ? fallbackPeak
  : reportPeak;
const treePeak = (reportTreePeak === undefined || reportTreePeak === null || Number(reportTreePeak) === 0) && fallbackTreePeak !== null
  ? fallbackTreePeak
  : reportTreePeak;
const peakSource = (reportPeak === undefined || reportPeak === null || Number(reportPeak) === 0) && fallbackPeak !== null
  ? "stdout_fallback"
  : "report";
const status = data.status ?? "unknown";
const exitCode = data.exit_code ?? "na";
const line = [
  `status=${status}`,
  `exit_code=${exitCode}`,
  `haxe_mode=${data.haxe_bin_mode ?? "na"}`,
  `haxe_policy=${data.haxe_bin_policy ?? "na"}`,
  `peak_rss_mb=${peak ?? "na"}`,
  `peak_tree_rss_mb=${treePeak ?? "na"}`,
  `peak_rss_source=${peakSource}`,
  `samples=${obs.heartbeat_samples ?? "na"}`,
  `emit_sec=${phase.emit ?? "na"}`,
  `total_sec=${phase.total ?? "na"}`,
  `heartbeat_trace_file=${obs.heartbeat_trace_file || "na"}`
].join(" ");
console.log(line);
' "$REPORT_JSON" "$RUN_STDOUT" | tee "$SUMMARY_FILE"

if [ -f "$PROGRESS_SUMMARY_SCRIPT" ]; then
	node "$PROGRESS_SUMMARY_SCRIPT" \
		--input "$PROGRESS_LOG" \
		--top 10 \
		--json-out "$PROGRESS_SUMMARY_JSON" | tee -a "$SUMMARY_FILE"
else
	echo "top_class_total_dt_ms: summary-script-missing" | tee -a "$SUMMARY_FILE"
	echo "output_checkpoints: none" | tee -a "$SUMMARY_FILE"
fi

if [ -f "$HEARTBEAT_SUMMARY_SCRIPT" ]; then
	node "$HEARTBEAT_SUMMARY_SCRIPT" \
		--input "$HEARTBEAT_TRACE" \
		--top 5 \
		--json-out "$HEARTBEAT_SUMMARY_JSON" | tee -a "$SUMMARY_FILE"
else
	echo "heartbeat_trace_summary: summary-script-missing" | tee -a "$SUMMARY_FILE"
fi

echo "stdout_log=$RUN_STDOUT" | tee -a "$SUMMARY_FILE"
echo "stderr_log=$RUN_STDERR" | tee -a "$SUMMARY_FILE"
echo "report_json=$REPORT_JSON" | tee -a "$SUMMARY_FILE"
echo "progress_log=$PROGRESS_LOG" | tee -a "$SUMMARY_FILE"
echo "progress_summary_json=$PROGRESS_SUMMARY_JSON" | tee -a "$SUMMARY_FILE"
echo "heartbeat_summary_json=$HEARTBEAT_SUMMARY_JSON" | tee -a "$SUMMARY_FILE"
echo "capacity_report_json=$CAPACITY_REPORT" | tee -a "$SUMMARY_FILE"

if [ "$run_code" != "0" ]; then
	echo "Profile run exited non-zero (code=$run_code). Summary artifacts are still available." | tee -a "$SUMMARY_FILE"
fi

artifact_error=0
if [ "$run_code" = "0" ]; then
	if [ ! -s "$REPORT_JSON" ]; then
		echo "Profile run completed but the required regeneration report is missing or empty: $REPORT_JSON" | tee -a "$SUMMARY_FILE" >&2
		artifact_error=1
	fi
	if [ ! -s "$PROGRESS_LOG" ]; then
		echo "Profile run completed but required progress telemetry is missing or empty: $PROGRESS_LOG" | tee -a "$SUMMARY_FILE" >&2
		artifact_error=1
	fi
	if [ ! -s "$PROGRESS_SUMMARY_JSON" ]; then
		echo "Profile run completed but the required progress summary is missing or empty: $PROGRESS_SUMMARY_JSON" | tee -a "$SUMMARY_FILE" >&2
		artifact_error=1
	fi
fi

if [ "$artifact_error" = "1" ]; then
	echo "Profile evidence is incomplete; rerun after correcting the artifact path or telemetry setup." | tee -a "$SUMMARY_FILE" >&2
	exit 3
fi

if [ "$run_code" != "0" ]; then
	exit "$run_code"
fi

exit 0
