#!/usr/bin/env bash
set -euo pipefail

# Proves whether one long-lived upstream Haxe 4.3.7 server materially shortens
# the complete hxhx -> reflaxe.ocaml -> native executable loop. Reflaxe owns a
# disposable generated-source tree; Dune owns a stable external build tree.
# The second request must reproduce the first tree, binary, and `--version`
# behavior rather than relying on stale generated files.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_PACKAGE="$ROOT/packages/hxhx"
SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
CAPACITY_HELPER="$ROOT/scripts/hxhx/check-local-capacity.js"
EVIDENCE_HELPER="$ROOT/scripts/ci/compiler-scale-reflaxe-server-evidence.js"
WATCHDOG_HELPER="$ROOT/scripts/hxhx/stage0-process-watchdog.sh"
PROGRESS_SUMMARY_HELPER="$ROOT/scripts/hxhx/summarize-stage0-progress.js"

HAXE_BIN="${HAXE_BIN:-haxe}"
RUN_ID="${HXHX_COMPILER_SCALE_SERVER_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
REPORT_DIR="${HXHX_COMPILER_SCALE_SERVER_REPORT_DIR:-$ROOT/.artifacts/hxhx/compiler-scale-reflaxe-server/$RUN_ID}"
OUTPUT_DIR="$REPORT_DIR/generated/out"
BUILD_DIR="$REPORT_DIR/dune-build"
SERVER_STATE_DIR="$REPORT_DIR/server-state"
SERVER_PORT="${HXHX_COMPILER_SCALE_SERVER_PORT:-$((26000 + ($$ % 8000)))}"
RSS_SAMPLES_FILE="$REPORT_DIR/server-rss-kb.samples"
SERVER_PROGRESS_FILE="$REPORT_DIR/logs/reflaxe-server-progress.log"
GENERATION_CEILING_SECS="${HXHX_COMPILER_SCALE_GENERATION_CEILING_SECS:-3000}"
DUNE_CEILING_SECS="${HXHX_COMPILER_SCALE_DUNE_CEILING_SECS:-1800}"
HEARTBEAT_SECS="${HXHX_COMPILER_SCALE_HEARTBEAT_SECS:-20}"
DUNE_JOBS="${HXHX_COMPILER_SCALE_DUNE_JOBS:-auto}"
CAPACITY_POLICY="${HXHX_COMPILER_SCALE_CAPACITY_POLICY:-require}"
CAPACITY_WAIT_SECS="${HXHX_COMPILER_SCALE_CAPACITY_WAIT_SECS:-1800}"
MINIMUM_ABSOLUTE_SAVED_MS="${HXHX_COMPILER_SCALE_MINIMUM_SAVED_MS:-120000}"
MAXIMUM_WARM_TO_COLD_RATIO="${HXHX_COMPILER_SCALE_MAXIMUM_WARM_TO_COLD_RATIO:-0.80}"
CEILING_RATIONALE="${HXHX_COMPILER_SCALE_CEILING_RATIONALE:-A 300-second profile completed Haxe typing in about 2 seconds, then spent about 250 seconds preparing Reflaxe macro/JIT execution before ordinary class rendering. Recent exact full source generation was about 2079 seconds, so 3000 seconds covers measured generation plus headroom without an unbounded wait.}"

CAPACITY_LEASE_OWNER_PID="${HXHX_HEAVY_RUN_LEASE_OWNER_PID:-$$}"
CAPACITY_LEASE_PRIMARY_OWNER=0
CAPACITY_LEASE_ACTIVE=0
SERVER_STARTED=0
SOURCE_CLEAN_AT_START=false
PROFILE_ONLY=0

if [[ -z "${HXHX_HEAVY_RUN_LEASE_OWNER_PID:-}" ]]; then
	CAPACITY_LEASE_PRIMARY_OWNER=1
	export HXHX_HEAVY_RUN_LEASE_OWNER_PID="$CAPACITY_LEASE_OWNER_PID"
fi

fail() {
	echo "compiler-scale Reflaxe server proof: $*" >&2
	exit 1
}

usage() {
	cat <<'USAGE'
Usage: bash scripts/hxhx/run-compiler-scale-reflaxe-server-proof.sh [--profile-only]

This checkpoint proof runs one compiler-scale cold request and one unchanged
warm request against the same upstream Haxe 4.3.7 server. It writes only under
its report directory; it never replaces the tracked bootstrap snapshot.

`--profile-only` runs one cold source-generation request with per-class Reflaxe
telemetry, then stops before Dune or the warm request. Use it to identify a
measured target-generation bottleneck before changing implementation. It does
not produce or satisfy the cold/warm performance report.

Important environment knobs:
  HAXE_BIN                                      Native Haxe 4.3.7 executable
  HXHX_COMPILER_SCALE_SERVER_REPORT_DIR        New evidence directory
  HXHX_COMPILER_SCALE_GENERATION_CEILING_SECS  Per-request ceiling (default 3000)
  HXHX_COMPILER_SCALE_DUNE_CEILING_SECS        Per-build ceiling (default 1800)
  HXHX_COMPILER_SCALE_HEARTBEAT_SECS           Progress/RSS interval (default 20)
  HXHX_COMPILER_SCALE_DUNE_JOBS                auto or positive integer
  HXHX_COMPILER_SCALE_CAPACITY_POLICY          auto|require|warn|off
  HXHX_COMPILER_SCALE_CAPACITY_WAIT_SECS       Capacity wait (default 1800)
  HXHX_COMPILER_SCALE_MINIMUM_SAVED_MS         Material absolute saving (default 120000)
  HXHX_COMPILER_SCALE_MAXIMUM_WARM_TO_COLD_RATIO
                                                 Material ratio alternative (default 0.80)

The final report passes only when cold and warm source, manifest, executable,
and version behavior match and the warm full loop saves at least two minutes
or twenty percent. Those are alternatives because a multi-minute absolute
saving is useful even when a large native link keeps the relative ratio high.
USAGE
}

non_negative_integer() {
	[[ "$1" =~ ^[0-9]+$ ]]
}

positive_integer() {
	[[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]
}

milliseconds() {
	node -e 'process.stdout.write(String(Date.now()))'
}

tracked_source_clean() {
	git -C "$ROOT" diff --quiet --ignore-submodules -- \
		&& git -C "$ROOT" diff --cached --quiet --ignore-submodules --
}

server_env() {
	HXHX_STATE_DIR="$SERVER_STATE_DIR" \
		HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
		HAXE_BIN="$HAXE_BIN" \
		REFLAXE_OCAML_PROGRESS_FILE="$SERVER_PROGRESS_FILE" \
		"$@"
}

server_rss_kb() {
	local total=0
	local pid=""
	local rss=""
	while IFS= read -r pid; do
		[[ "$pid" =~ ^[0-9]+$ ]] || continue
		rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
		if [[ "$rss" =~ ^[0-9]+$ ]]; then
			total="$((total + rss))"
		fi
	done < <(server_env bash "$SERVER_HELPER" owned-pids)
	printf '%s\n' "$total"
}

sample_server_rss() {
	local current
	current="$(server_rss_kb)"
	printf '%s\n' "$current" >>"$RSS_SAMPLES_FILE"
	printf '%s\n' "$current"
}

file_size_bytes() {
	local file="$1"
	if [[ -f "$file" ]]; then
		wc -c <"$file" | tr -d ' '
	else
		printf '0\n'
	fi
}

private_candidate_count() {
	find "$REPORT_DIR/generated" -type d \
		\( -name '.*.reflaxe-output-transaction' -o -name '.*.reflaxe-output-candidate' \) \
		-print 2>/dev/null | wc -l | tr -d ' '
}

pid_state_count() {
	local count=0
	for file in "$SERVER_STATE_DIR/haxe-server.pid" "$SERVER_STATE_DIR/haxe-server.pids"; do
		[[ -e "$file" ]] && count="$((count + 1))"
	done
	printf '%s\n' "$count"
}

count_owned_pids_after_stop() {
	local owned_pids=""
	# The ownership helper returns 1 when the desired post-stop result is an
	# empty list. Normalize that state before counting so pipefail does not
	# abort the evidence report after a successful cleanup.
	owned_pids="$(server_env bash "$SERVER_HELPER" owned-pids 2>/dev/null || true)"
	printf '%s\n' "$owned_pids" | awk '/^[0-9]+$/ { count++ } END { print count + 0 }'
}

release_capacity_lease() {
	if [[ "$CAPACITY_LEASE_PRIMARY_OWNER" = "1" && "$CAPACITY_LEASE_ACTIVE" = "1" ]]; then
		node "$CAPACITY_HELPER" \
			--release-lease \
			--lease-owner-pid "$CAPACITY_LEASE_OWNER_PID" >/dev/null 2>&1 || true
	fi
}

cleanup() {
	if [[ "$SERVER_STARTED" = "1" ]]; then
		server_env bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true
		SERVER_STARTED=0
	fi
	release_capacity_lease
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_bounded() {
	local label="$1"
	local ceiling="$2"
	local log_file="$3"
	shift 3
	local started
	local elapsed=0
	local pid=""
	local code=0
	local rss=0
	local progress_file="$SERVER_PROGRESS_FILE"
	local timeout_kind="none"
	local last_heartbeat=0
	local completed_ms=0

	started="$(milliseconds)"
	set +e
	REFLAXE_OCAML_PROGRESS_FILE="$progress_file" "$@" >"$log_file" 2>&1 &
	pid="$!"
	set -e

	while kill -0 "$pid" >/dev/null 2>&1; do
		sleep 1
		if ! kill -0 "$pid" >/dev/null 2>&1; then
			break
		fi
		elapsed="$(( ($(milliseconds) - started) / 1000 ))"
		if (( elapsed - last_heartbeat >= HEARTBEAT_SECS )); then
			last_heartbeat="$elapsed"
			rss="$(sample_server_rss)"
			echo "== $label heartbeat: elapsed=${elapsed}s server_rss_kb=$rss progress_bytes=$(file_size_bytes "$progress_file")" >&2
		fi
		if (( ceiling > 0 && elapsed >= ceiling )); then
			timeout_kind="hard"
			stage0_watchdog_terminate_process_tree "$pid"
			break
		fi
	done

	set +e
	wait "$pid"
	code="$?"
	set -e
	if [[ "$timeout_kind" != "none" ]]; then
		fail "$label exceeded its measured ${ceiling}s ceiling; log=$log_file"
	fi
	if [[ "$code" -ne 0 ]]; then
		sed -n '1,240p' "$log_file" >&2 || true
		fail "$label failed with exit $code; log=$log_file"
	fi
	completed_ms="$(( $(milliseconds) - started ))"
	printf '%s\n' "$completed_ms" >"$REPORT_DIR/logs/$label.elapsed-ms"
	printf '%s\n' "$completed_ms"
}

run_generation() {
	local label="$1"
	local log_file="$REPORT_DIR/logs/$label.haxe.log"
	local telemetry_define="reflaxe_ocaml_progress"
	if [[ "$PROFILE_ONLY" = "1" ]]; then
		telemetry_define="reflaxe_ocaml_telemetry"
	fi
	(
		cd "$HAXE_PACKAGE"
		run_bounded "$label" "$GENERATION_CEILING_SECS" "$log_file" \
			"$HAXE_BIN" \
			build.hxml \
			-D reflaxe_output_transaction \
			-D ocaml_no_build \
			-D reflaxe.dont_output_metadata_id \
			-D "$telemetry_define" \
			-D "ocaml_output=$OUTPUT_DIR" \
			--connect "$SERVER_PORT"
	)
}

run_dune() {
	local label="$1"
	local log_file="$REPORT_DIR/logs/$label.dune.log"
	local -a command=(dune build --root "$OUTPUT_DIR" --build-dir "$BUILD_DIR")
	if [[ "$DUNE_JOBS" != "auto" ]]; then
		command+=(-j "$DUNE_JOBS")
	fi
	command+=(./out.exe)
	run_bounded "$label" "$DUNE_CEILING_SECS" "$log_file" "${command[@]}"
}

capture_state() {
	local label="$1"
	local executable="$BUILD_DIR/default/out.exe"
	local version_stdout="$REPORT_DIR/logs/$label.version.stdout"
	local version_stderr="$REPORT_DIR/logs/$label.version.stderr"
	local version_exit=0
	[[ -x "$executable" ]] || fail "$label native executable is missing: $executable"
	set +e
	"$executable" --version >"$version_stdout" 2>"$version_stderr"
	version_exit="$?"
	set -e
	node "$EVIDENCE_HELPER" capture \
		--output-dir "$OUTPUT_DIR" \
		--executable "$executable" \
		--version-stdout "$version_stdout" \
		--version-stderr "$version_stderr" \
		--version-exit "$version_exit" \
		--out "$REPORT_DIR/$label.capture.json" >/dev/null
	cp "$OUTPUT_DIR/ocaml_artifact_manifest.json" "$REPORT_DIR/$label.ocaml_artifact_manifest.json"
	cp "$OUTPUT_DIR/_GeneratedFiles.json" "$REPORT_DIR/$label._GeneratedFiles.json"
	cp "$executable" "$REPORT_DIR/$label.out.exe"
}

while [[ "$#" -gt 0 ]]; do
	case "$1" in
		--profile-only)
			PROFILE_ONLY=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			fail "unexpected argument '$1'; use --help"
			;;
	esac
done

source "$WATCHDOG_HELPER"
for command in git node dune ocamlopt ps find; do
	command -v "$command" >/dev/null 2>&1 || fail "missing required command: $command"
done
command -v "$HAXE_BIN" >/dev/null 2>&1 || fail "missing Haxe executable: $HAXE_BIN"
[[ -x "$SERVER_HELPER" ]] || fail "missing Haxe server helper: $SERVER_HELPER"
[[ -f "$CAPACITY_HELPER" ]] || fail "missing capacity helper: $CAPACITY_HELPER"
[[ -f "$EVIDENCE_HELPER" ]] || fail "missing evidence helper: $EVIDENCE_HELPER"
[[ -f "$PROGRESS_SUMMARY_HELPER" ]] || fail "missing progress summary helper: $PROGRESS_SUMMARY_HELPER"
positive_integer "$GENERATION_CEILING_SECS" || fail "generation ceiling must be a positive integer"
positive_integer "$DUNE_CEILING_SECS" || fail "Dune ceiling must be a positive integer"
positive_integer "$HEARTBEAT_SECS" || fail "heartbeat must be a positive integer"
non_negative_integer "$MINIMUM_ABSOLUTE_SAVED_MS" || fail "minimum saved milliseconds must be non-negative"
case "$DUNE_JOBS" in
	auto) ;;
	''|*[!0-9]*|0) fail "Dune jobs must be auto or a positive integer" ;;
esac
case "$CAPACITY_POLICY" in
	auto|require|warn|off) ;;
	*) fail "capacity policy must be auto, require, warn, or off" ;;
esac

HAXE_VERSION="$("$HAXE_BIN" --version | head -n 1 | tr -d '\r')"
[[ "$HAXE_VERSION" = "4.3.7" ]] || fail "expected upstream Haxe 4.3.7, got '$HAXE_VERSION'"
[[ ! -e "$REPORT_DIR" ]] || fail "report directory already exists: $REPORT_DIR"
tracked_source_clean && SOURCE_CLEAN_AT_START=true
[[ "$SOURCE_CLEAN_AT_START" = "true" ]] || fail "tracked source must be clean before an evidence run"
mkdir -p "$REPORT_DIR/logs" "$REPORT_DIR/generated"

node "$CAPACITY_HELPER" \
	--policy "$CAPACITY_POLICY" \
	--wait-seconds "$CAPACITY_WAIT_SECS" \
	--lease-owner-pid "$CAPACITY_LEASE_OWNER_PID" \
	--label compiler-scale-reflaxe-server \
	--json-out "$REPORT_DIR/capacity_report.json"
CAPACITY_LEASE_ACTIVE=1

server_env bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true
server_env bash "$SERVER_HELPER" start
SERVER_STARTED=1
RSS_BASELINE_KB="$(sample_server_rss)"

echo "== Compiler-scale Reflaxe server proof"
echo "Commit: $(git -C "$ROOT" rev-parse HEAD)"
echo "Haxe: $HAXE_BIN ($HAXE_VERSION)"
echo "Report: $REPORT_DIR"
echo "Ceilings: generation=${GENERATION_CEILING_SECS}s dune=${DUNE_CEILING_SECS}s"

COLD_GENERATION_MS="$(run_generation cold-generation)"
RSS_AFTER_COLD_KB="$(sample_server_rss)"

if [[ "$PROFILE_ONLY" = "1" ]]; then
	RSS_PEAK_KB="$(awk 'BEGIN { peak = 0 } /^[0-9]+$/ && $1 > peak { peak = $1 } END { print peak }' "$RSS_SAMPLES_FILE")"
	server_env bash "$SERVER_HELPER" stop
	SERVER_STARTED=0
	OWNED_PIDS_AFTER_STOP="$(count_owned_pids_after_stop)"
	PRIVATE_CANDIDATES_AFTER_STOP="$(private_candidate_count)"
	PID_STATE_AFTER_STOP="$(pid_state_count)"
	[[ "$OWNED_PIDS_AFTER_STOP" = "0" ]] || fail "profile cleanup left $OWNED_PIDS_AFTER_STOP owned server process(es)"
	[[ "$PRIVATE_CANDIDATES_AFTER_STOP" = "0" ]] || fail "profile cleanup left $PRIVATE_CANDIDATES_AFTER_STOP private output candidate(s)"
	[[ "$PID_STATE_AFTER_STOP" = "0" ]] || fail "profile cleanup left $PID_STATE_AFTER_STOP server PID-state file(s)"
	tracked_source_clean || fail "profile changed tracked source"
	node "$PROGRESS_SUMMARY_HELPER" \
		--input "$SERVER_PROGRESS_FILE" \
		--top 20 \
		--json-out "$REPORT_DIR/progress-summary.json" \
		--text-out "$REPORT_DIR/progress-summary.txt"
	node -e '
const fs = require("fs")
const report = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
if (!Number.isInteger(report.class_end_total_samples) || report.class_end_total_samples <= 0) {
  console.error("compiler-scale Reflaxe profile: detailed class telemetry is missing")
  process.exit(1)
}
' "$REPORT_DIR/progress-summary.json"
	release_capacity_lease
	CAPACITY_LEASE_ACTIVE=0
	echo "Compiler-scale Reflaxe profile: generation_ms=$COLD_GENERATION_MS peak_rss_kb=$RSS_PEAK_KB"
	echo "Profile summary: $REPORT_DIR/progress-summary.json"
	exit 0
fi

COLD_DUNE_MS="$(run_dune cold-dune)"
capture_state cold

WARM_GENERATION_MS="$(run_generation warm-generation)"
RSS_AFTER_WARM_KB="$(sample_server_rss)"
WARM_DUNE_MS="$(run_dune warm-dune)"
capture_state warm
RSS_FINAL_KB="$(sample_server_rss)"
RSS_PEAK_KB="$(awk 'BEGIN { peak = 0 } /^[0-9]+$/ && $1 > peak { peak = $1 } END { print peak }' "$RSS_SAMPLES_FILE")"

server_env bash "$SERVER_HELPER" stop
SERVER_STARTED=0
OWNED_PIDS_AFTER_STOP="$(count_owned_pids_after_stop)"
PRIVATE_CANDIDATES_AFTER_STOP="$(private_candidate_count)"
PID_STATE_AFTER_STOP="$(pid_state_count)"
SOURCE_CLEAN_AT_END=false
tracked_source_clean && SOURCE_CLEAN_AT_END=true

node "$EVIDENCE_HELPER" report \
	--cold-capture "$REPORT_DIR/cold.capture.json" \
	--warm-capture "$REPORT_DIR/warm.capture.json" \
	--capacity-report "$REPORT_DIR/capacity_report.json" \
	--source-commit "$(git -C "$ROOT" rev-parse HEAD)" \
	--source-clean-at-start "$SOURCE_CLEAN_AT_START" \
	--source-clean-at-end "$SOURCE_CLEAN_AT_END" \
	--haxe-bin "$(command -v "$HAXE_BIN")" \
	--haxe-version "$HAXE_VERSION" \
	--ocamlopt-version "$(ocamlopt -version)" \
	--dune-version "$(dune --version)" \
	--generation-ceiling-seconds "$GENERATION_CEILING_SECS" \
	--dune-ceiling-seconds "$DUNE_CEILING_SECS" \
	--ceiling-rationale "$CEILING_RATIONALE" \
	--cold-generation-ms "$COLD_GENERATION_MS" \
	--cold-dune-ms "$COLD_DUNE_MS" \
	--warm-generation-ms "$WARM_GENERATION_MS" \
	--warm-dune-ms "$WARM_DUNE_MS" \
	--minimum-absolute-saved-ms "$MINIMUM_ABSOLUTE_SAVED_MS" \
	--maximum-warm-to-cold-ratio "$MAXIMUM_WARM_TO_COLD_RATIO" \
	--rss-baseline-kb "$RSS_BASELINE_KB" \
	--rss-after-cold-kb "$RSS_AFTER_COLD_KB" \
	--rss-after-warm-kb "$RSS_AFTER_WARM_KB" \
	--rss-peak-kb "$RSS_PEAK_KB" \
	--rss-final-kb "$RSS_FINAL_KB" \
	--owned-pids-after-stop "$OWNED_PIDS_AFTER_STOP" \
	--private-candidates-after-stop "$PRIVATE_CANDIDATES_AFTER_STOP" \
	--pid-state-after-stop "$PID_STATE_AFTER_STOP" \
	--out "$REPORT_DIR/report.json"

release_capacity_lease
CAPACITY_LEASE_ACTIVE=0
echo "Evidence: $REPORT_DIR/report.json"
