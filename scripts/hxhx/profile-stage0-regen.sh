#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGEN_SCRIPT="$ROOT/scripts/hxhx/regenerate-hxhx-bootstrap.sh"

POLICY="${HXHX_STAGE0_PROFILE_POLICY:-prefer-native}"
FAILFAST_SECS="${HXHX_STAGE0_PROFILE_FAILFAST_SECS:-120}"
HEARTBEAT_SECS="${HXHX_STAGE0_PROFILE_HEARTBEAT_SECS:-20}"
NO_OPT="${HXHX_STAGE0_PROFILE_NO_OPT:-0}"
NO_INLINE="${HXHX_STAGE0_PROFILE_NO_INLINE:-0}"
DISABLE_PREPASSES="${HXHX_STAGE0_PROFILE_DISABLE_PREPASSES:-0}"
STAGE0_OCAMLRUNPARAM="${HXHX_STAGE0_PROFILE_OCAMLRUNPARAM:-}"
SCENARIO_ARGS="${HXHX_STAGE0_PROFILE_SCENARIO_ARGS:---incremental --no-verify --force}"
TELEMETRY_DETAIL="${HXHX_STAGE0_PROFILE_TELEMETRY_DETAIL:-0}"
TELEMETRY_CLASS="${HXHX_STAGE0_PROFILE_TELEMETRY_CLASS:-}"
OUT_DIR="${HXHX_STAGE0_PROFILE_OUT_DIR:-$ROOT/.hxhx/profile/stage0-regen/$(date +%Y%m%d-%H%M%S)}"

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
  --disable-prepasses                            Enable stage0 prepass disable define
  --ocamlrunparam <value>                        Set OCAMLRUNPARAM for stage0 haxe process
  --telemetry-detail                             Enable detailed builder telemetry
  --telemetry-class <TypeName>                   Restrict detail telemetry to one class
  --scenario-args "<args>"                       Regen args string (default: --incremental --no-verify --force)
  --out-dir <dir>                                Output directory for artifacts/summary
  -h, --help                                     Show this help

Outputs:
  <out-dir>/regen_report.json
  <out-dir>/reflaxe_ocaml_progress.log
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
		--no-opt)
			NO_OPT=1
			shift
			;;
		--disable-prepasses)
			DISABLE_PREPASSES=1
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
assert_bool_01 "DISABLE_PREPASSES" "$DISABLE_PREPASSES"
assert_bool_01 "TELEMETRY_DETAIL" "$TELEMETRY_DETAIL"

if [ ! -x "$REGEN_SCRIPT" ]; then
	echo "Missing regen script: $REGEN_SCRIPT" >&2
	exit 2
fi

mkdir -p "$OUT_DIR"
REPORT_JSON="$OUT_DIR/regen_report.json"
PROGRESS_LOG="$OUT_DIR/reflaxe_ocaml_progress.log"
SUMMARY_FILE="$OUT_DIR/summary.txt"
RUN_STDOUT="$OUT_DIR/run.stdout.log"
RUN_STDERR="$OUT_DIR/run.stderr.log"

echo "== Stage0 regen profile run"
echo "policy=$POLICY failfast=${FAILFAST_SECS}s heartbeat=${HEARTBEAT_SECS}s no_opt=$NO_OPT no_inline=$NO_INLINE disable_prepasses=$DISABLE_PREPASSES ocamlrunparam=${STAGE0_OCAMLRUNPARAM:-<unset>} telemetry_detail=$TELEMETRY_DETAIL"
echo "out_dir=$OUT_DIR"

set +e
REFLAXE_OCAML_PROGRESS_FILE="$PROGRESS_LOG" \
HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY="$POLICY" \
HXHX_STAGE0_FAILFAST_SECS="$FAILFAST_SECS" \
HXHX_STAGE0_HEARTBEAT="$HEARTBEAT_SECS" \
HXHX_STAGE0_TELEMETRY=1 \
HXHX_STAGE0_TELEMETRY_DETAIL="$TELEMETRY_DETAIL" \
HXHX_STAGE0_TELEMETRY_CLASS="$TELEMETRY_CLASS" \
HXHX_STAGE0_NO_OPT="$NO_OPT" \
HXHX_STAGE0_NO_INLINE="$NO_INLINE" \
HXHX_STAGE0_DISABLE_PREPASSES="$DISABLE_PREPASSES" \
HXHX_STAGE0_OCAMLRUNPARAM="$STAGE0_OCAMLRUNPARAM" \
bash "$REGEN_SCRIPT" $SCENARIO_ARGS --report-json "$REPORT_JSON" >"$RUN_STDOUT" 2>"$RUN_STDERR"
run_code="$?"
set -e

node -e '
const fs = require("fs");
const path = process.argv[1];
let data = {};
try {
  data = JSON.parse(fs.readFileSync(path, "utf8"));
} catch (_) {}
const phase = data.phase_seconds || {};
const obs = data.stage0_observability || {};
const status = data.status ?? "unknown";
const exitCode = data.exit_code ?? "na";
const line = [
  `status=${status}`,
  `exit_code=${exitCode}`,
  `haxe_mode=${data.haxe_bin_mode ?? "na"}`,
  `haxe_policy=${data.haxe_bin_policy ?? "na"}`,
  `peak_rss_mb=${obs.heartbeat_peak_rss_mb ?? "na"}`,
  `samples=${obs.heartbeat_samples ?? "na"}`,
  `emit_sec=${phase.emit ?? "na"}`,
  `total_sec=${phase.total ?? "na"}`
].join(" ");
console.log(line);
' "$REPORT_JSON" | tee "$SUMMARY_FILE"

node -e '
const fs = require("fs");
const path = process.argv[1];
if (!fs.existsSync(path)) {
  console.log("top_class_end_dt_ms: no-progress-log");
  process.exit(0);
}
const lines = fs.readFileSync(path, "utf8").split(/\r?\n/);
const classRows = [];
const checkpointRows = [];
for (const line of lines) {
  let m = line.match(/class_end count=\d+ name=([^ ]+) dt_ms=(\d+)/);
  if (m) {
    classRows.push({ name: m[1], dt: Number(m[2]) });
    continue;
  }
  m = line.match(/onOutputComplete ([^=]+) dt=(\d+)s/);
  if (m) checkpointRows.push({ phase: m[1].trim(), dt: Number(m[2]) });
}
if (classRows.length === 0) {
  console.log("top_class_end_dt_ms: none");
} else {
  classRows.sort((a, b) => b.dt - a.dt);
  console.log("top_class_end_dt_ms:");
  for (const row of classRows.slice(0, 10)) {
    console.log(`  ${row.dt}\t${row.name}`);
  }
}
if (checkpointRows.length === 0) {
  console.log("output_checkpoints: none");
} else {
  console.log("output_checkpoints:");
  for (const row of checkpointRows) {
    console.log(`  ${row.dt}s\t${row.phase}`);
  }
}
' "$PROGRESS_LOG" | tee -a "$SUMMARY_FILE"

echo "stdout_log=$RUN_STDOUT" | tee -a "$SUMMARY_FILE"
echo "stderr_log=$RUN_STDERR" | tee -a "$SUMMARY_FILE"
echo "report_json=$REPORT_JSON" | tee -a "$SUMMARY_FILE"
echo "progress_log=$PROGRESS_LOG" | tee -a "$SUMMARY_FILE"

if [ "$run_code" != "0" ]; then
	echo "Profile run exited non-zero (code=$run_code). Summary artifacts are still available." | tee -a "$SUMMARY_FILE"
fi

exit 0
