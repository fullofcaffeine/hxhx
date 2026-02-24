#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGEN_SCRIPT="$ROOT/scripts/hxhx/regenerate-hxhx-bootstrap.sh"
SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
STATE_DIR="${HXHX_STATE_DIR:-$ROOT/.hxhx/state}"
FINGERPRINT_FILE="$STATE_DIR/bootstrap_regen_fingerprint.v1"

HAXE_BIN="${HAXE_BIN:-haxe}"
REPS="${HXHX_BOOTSTRAP_BENCH_REPS:-1}"
SCENARIOS_RAW="${HXHX_BOOTSTRAP_BENCH_SCENARIOS:-cold,warm,skip}"
VERIFY_FLAG="${HXHX_BOOTSTRAP_BENCH_VERIFY:-0}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_DIR="${HXHX_BOOTSTRAP_BENCH_REPORT_DIR:-$ROOT/.hxhx/bench/bootstrap-regen/$TIMESTAMP}"

usage() {
	cat <<'USAGE'
Usage: bash scripts/hxhx/bench-bootstrap-regen.sh

Environment knobs:
  HAXE_BIN                             Haxe executable path (default: haxe)
  HXHX_BOOTSTRAP_BENCH_REPS           Repetitions per scenario (default: 1)
  HXHX_BOOTSTRAP_BENCH_SCENARIOS      Comma list: cold,warm,skip (default: cold,warm,skip)
  HXHX_BOOTSTRAP_BENCH_VERIFY         0/1 run snapshot verify step (default: 0)
  HXHX_BOOTSTRAP_BENCH_REPORT_DIR     Output directory for per-run JSON reports

Examples:
  # Run warm + skip only (faster local loop)
  HXHX_BOOTSTRAP_BENCH_SCENARIOS=warm,skip bash scripts/hxhx/bench-bootstrap-regen.sh

  # Include verify and 2 reps
  HXHX_BOOTSTRAP_BENCH_VERIFY=1 HXHX_BOOTSTRAP_BENCH_REPS=2 bash scripts/hxhx/bench-bootstrap-regen.sh
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

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	usage
	exit 0
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
	echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
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

if ! is_non_negative_int "$REPS" || [ "$REPS" = "0" ]; then
	echo "Invalid HXHX_BOOTSTRAP_BENCH_REPS: '$REPS' (expected positive integer)." >&2
	exit 1
fi

if ! is_non_negative_int "$VERIFY_FLAG"; then
	echo "Invalid HXHX_BOOTSTRAP_BENCH_VERIFY: '$VERIFY_FLAG' (expected 0 or 1)." >&2
	exit 1
fi

mkdir -p "$REPORT_DIR"
RESULTS_TSV="$REPORT_DIR/results.tsv"
: >"$RESULTS_TSV"

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
echo "Reports: $REPORT_DIR"
echo ""

run_once() {
	local scenario="$1"
	local rep="$2"
	shift 2
	local report_path="$REPORT_DIR/${scenario}.run${rep}.json"
	local start_ts end_ts elapsed

	start_ts="$(date +%s)"
	HAXE_BIN="$HAXE_BIN" bash "$REGEN_SCRIPT" "$@" "${verify_args[@]}" --report-json "$report_path"
	end_ts="$(date +%s)"
	elapsed="$((end_ts - start_ts))"

	printf '%s\t%s\t%s\t%s\n' "$scenario" "$rep" "$elapsed" "$report_path" >>"$RESULTS_TSV"
	printf 'run %-5s #%s  %4ss  report=%s\n' "$scenario" "$rep" "$elapsed" "$report_path"
}

prime_skip_fingerprint_if_needed() {
	if [ -f "$FINGERPRINT_FILE" ]; then
		return
	fi
	echo "Priming fingerprint for skip scenario (one warm force run, not measured)..."
	HAXE_BIN="$HAXE_BIN" bash "$REGEN_SCRIPT" --incremental --use-repo-server --keep-repo-server --force --no-verify >/dev/null
}

run_scenario_cold() {
	local rep
	for rep in $(seq 1 "$REPS"); do
		bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true
		run_once "cold" "$rep" --full --clean-out --force
	done
}

run_scenario_warm() {
	local rep
	for rep in $(seq 1 "$REPS"); do
		run_once "warm" "$rep" --incremental --use-repo-server --keep-repo-server --force
	done
}

run_scenario_skip() {
	prime_skip_fingerprint_if_needed
	local rep
	for rep in $(seq 1 "$REPS"); do
		run_once "skip" "$rep" --incremental --use-repo-server --keep-repo-server --skip-if-unchanged
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
		'')
			;;
		*)
			echo "Unknown scenario '$scenario'. Allowed values: cold,warm,skip." >&2
			exit 1
			;;
	esac
done

echo ""
echo "== Summary (seconds)"
awk -F '\t' '
{
	sc = $1
	sec = $3 + 0
	if (!(sc in count)) {
		count[sc] = 0
		sum[sc] = 0
		best[sc] = sec
		worst[sc] = sec
	}
	count[sc]++
	sum[sc] += sec
	if (sec < best[sc]) best[sc] = sec
	if (sec > worst[sc]) worst[sc] = sec
}
END {
	printf "%-8s %-6s %-6s %-6s %-6s\n", "scenario", "runs", "avg", "best", "worst"
	for (sc in count) {
		avg = int(sum[sc] / count[sc])
		printf "%-8s %-6d %-6d %-6d %-6d\n", sc, count[sc], avg, best[sc], worst[sc]
	}
}
' "$RESULTS_TSV"

echo ""
echo "Detailed results: $RESULTS_TSV"
