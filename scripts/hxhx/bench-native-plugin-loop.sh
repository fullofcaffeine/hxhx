#!/usr/bin/env bash
set -euo pipefail

# Measure the target-author loop, not only generated application runtime:
# build a real OCaml plugin, load it into hxhx, compile a sample, and run it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_BUILDER="$ROOT/scripts/ci/native-plugin-loop-benchmark-report.js"
UPSTREAM_PROOF="$ROOT/scripts/ci/run-full1-plugin-upstream-to-hxhx-proof.sh"
HXHX_PROOF="$ROOT/scripts/ci/run-full1-plugin-hxhx-to-hxhx-proof.sh"

REPS="${HXHX_NATIVE_PLUGIN_LOOP_REPS:-2}"
WARMUPS="${HXHX_NATIVE_PLUGIN_LOOP_WARMUPS:-1}"
RUN_ID="${HXHX_NATIVE_PLUGIN_LOOP_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
REPORT_DIR="${HXHX_NATIVE_PLUGIN_LOOP_REPORT_DIR:-$ROOT/.artifacts/hxhx/native-plugin-loop/$RUN_ID}"
REPORT_JSON="$REPORT_DIR/report.json"
RESULTS_TSV="$REPORT_DIR/results.tsv"
HXHX_BIN_RESOLVED="${HXHX_NATIVE_PLUGIN_LOOP_HXHX_BIN:-${HXHX_BIN:-}}"
HXHX_BIN_COMMIT="${HXHX_NATIVE_PLUGIN_LOOP_HXHX_COMMIT:-}"
HXHX_DUNE_JOBS_VALUE="${HXHX_DUNE_JOBS:-auto}"

fail() {
	echo "native plugin-loop benchmark: $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

positive_integer() {
	case "$1" in
		''|*[!0-9]*|0)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

non_negative_integer() {
	case "$1" in
		''|*[!0-9]*)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

now_ms() {
	node -e 'process.stdout.write(String(Date.now()))'
}

tracked_source_clean() {
	git -C "$ROOT" diff --quiet --ignore-submodules -- \
		&& git -C "$ROOT" diff --cached --quiet --ignore-submodules --
}

absolute_path() {
	local input="$1"
	local dir
	dir="$(cd "$(dirname "$input")" && pwd)"
	printf '%s/%s\n' "$dir" "$(basename "$input")"
}

require_cmd git
require_cmd haxe
require_cmd node
require_cmd dune
require_cmd ocamlc
require_cmd ocamlopt
require_cmd shasum
[ -f "$REPORT_BUILDER" ] || fail "missing report builder: $REPORT_BUILDER"
[ -x "$UPSTREAM_PROOF" ] || fail "missing upstream plugin proof: $UPSTREAM_PROOF"
[ -x "$HXHX_PROOF" ] || fail "missing hxhx plugin proof: $HXHX_PROOF"
positive_integer "$REPS" || fail "HXHX_NATIVE_PLUGIN_LOOP_REPS must be a positive integer"
non_negative_integer "$WARMUPS" || fail "HXHX_NATIVE_PLUGIN_LOOP_WARMUPS must be a non-negative integer"

mkdir -p "$REPORT_DIR"
SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
SOURCE_CLEAN_AT_START=false
if tracked_source_clean; then
	SOURCE_CLEAN_AT_START=true
fi

hxhx_provided=true
preparation_start_ms="$(now_ms)"
if [ -z "$HXHX_BIN_RESOLVED" ]; then
	hxhx_provided=false
	HXHX_BIN_COMMIT="$SOURCE_COMMIT"
	prep_stdout="$REPORT_DIR/hxhx-preparation.stdout.log"
	prep_stderr="$REPORT_DIR/hxhx-preparation.stderr.log"
	set +e
	HXHX_FORBID_STAGE0=1 \
		HXHX_BOOTSTRAP_PREFER_NATIVE=1 \
		HXHX_STAGE0_OCAML_BUILD=native \
		HXHX_DUNE_JOBS="$HXHX_DUNE_JOBS_VALUE" \
		bash "$ROOT/scripts/hxhx/build-hxhx.sh" >"$prep_stdout" 2>"$prep_stderr"
	prep_status="$?"
	set -e
	if [ "$prep_status" -ne 0 ]; then
		cat "$prep_stdout" >&2 || true
		cat "$prep_stderr" >&2 || true
		fail "stage0-free native hxhx preparation failed with exit $prep_status"
	fi
	HXHX_BIN_RESOLVED="$(tail -n 1 "$prep_stdout" | tr -d '\r')"
fi
preparation_end_ms="$(now_ms)"
hxhx_preparation_ms="$((preparation_end_ms - preparation_start_ms))"

[ -n "$HXHX_BIN_RESOLVED" ] || fail "hxhx preparation did not return an artifact path"
if [ "$hxhx_provided" = "true" ]; then
	[[ "$HXHX_BIN_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]] \
		|| fail "HXHX_NATIVE_PLUGIN_LOOP_HXHX_COMMIT must be the 40-character source commit for a caller-provided hxhx binary"
fi
[ "$HXHX_BIN_COMMIT" = "$SOURCE_COMMIT" ] \
	|| fail "hxhx artifact commit $HXHX_BIN_COMMIT does not match benchmark commit $SOURCE_COMMIT"
HXHX_BIN_RESOLVED="$(absolute_path "$HXHX_BIN_RESOLVED")"
[ -x "$HXHX_BIN_RESOLVED" ] || fail "hxhx artifact is not executable: $HXHX_BIN_RESOLVED"
case "$HXHX_BIN_RESOLVED" in
	*.exe)
		;;
	*)
		fail "native timing evidence requires an hxhx .exe artifact; received $HXHX_BIN_RESOLVED"
		;;
esac

printf 'route\trep\torder\telapsed_ms\tsummary\n' >"$RESULTS_TSV"

run_proof() {
	local route="$1"
	local phase="$2"
	local rep="$3"
	local order="$4"
	local artifact_dir="$REPORT_DIR/proofs/${phase}.${rep}.${route}"
	local wrapper_log="$artifact_dir/benchmark-wrapper.log"
	local summary_path=""
	local start_ms end_ms elapsed_ms status

	mkdir -p "$artifact_dir"
	start_ms="$(now_ms)"
	set +e
	case "$route" in
		upstream-to-hxhx)
			GITHUB_SHA="$SOURCE_COMMIT" \
				GITHUB_RUN_ID="plugin-loop-$RUN_ID" \
				GITHUB_RUN_ATTEMPT="1" \
				FULL1_PLUGIN_UPSTREAM_ARTIFACT_DIR="$artifact_dir" \
				FULL1_PLUGIN_UPSTREAM_HXHX_BIN="$HXHX_BIN_RESOLVED" \
				HXHX_DUNE_JOBS="$HXHX_DUNE_JOBS_VALUE" \
				bash "$UPSTREAM_PROOF" >"$wrapper_log" 2>&1
			status="$?"
			summary_path="$artifact_dir/full1-plugin-upstream-to-hxhx.summary.json"
			;;
		hxhx-to-hxhx)
			GITHUB_SHA="$SOURCE_COMMIT" \
				GITHUB_RUN_ID="plugin-loop-$RUN_ID" \
				GITHUB_RUN_ATTEMPT="1" \
				FULL1_PLUGIN_HXHX_ARTIFACT_DIR="$artifact_dir" \
				FULL1_PLUGIN_HXHX_BIN="$HXHX_BIN_RESOLVED" \
				FULL1_PLUGIN_HXHX_FORCE_STAGE0_BUILD=0 \
				HXHX_DUNE_JOBS="$HXHX_DUNE_JOBS_VALUE" \
				bash "$HXHX_PROOF" >"$wrapper_log" 2>&1
			status="$?"
			summary_path="$artifact_dir/full1-plugin-hxhx-to-hxhx.summary.json"
			;;
		*)
			set -e
			fail "unknown proof route: $route"
			;;
	esac
	set -e
	end_ms="$(now_ms)"
	elapsed_ms="$((end_ms - start_ms))"

	if [ "$status" -ne 0 ]; then
		cat "$wrapper_log" >&2 || true
		fail "$route proof failed with exit $status"
	fi
	[ -f "$summary_path" ] || fail "$route proof did not write $summary_path"
	if [ "$phase" = "warmup" ]; then
		echo "warmup route=$route #$rep ${elapsed_ms}ms"
		rm -rf "$artifact_dir"
		return 0
	fi
	printf '%s\t%s\t%s\t%s\t%s\n' "$route" "$rep" "$order" "$elapsed_ms" "$summary_path" >>"$RESULTS_TSV"
	echo "sample route=$route #$rep order=$order ${elapsed_ms}ms"
}

echo "== Native plugin author-loop benchmark"
echo "Commit: $SOURCE_COMMIT"
echo "Native hxhx: $HXHX_BIN_RESOLVED"
echo "Native hxhx preparation: ${hxhx_preparation_ms}ms (excluded from samples)"
echo "Repetitions: $REPS"
echo "Warmups per route: $WARMUPS"
echo "Dune jobs: $HXHX_DUNE_JOBS_VALUE"
echo "Report directory: $REPORT_DIR"
echo ""

warmup=1
while [ "$warmup" -le "$WARMUPS" ]; do
	run_proof upstream-to-hxhx warmup "$warmup" 1
	run_proof hxhx-to-hxhx warmup "$warmup" 2
	warmup="$((warmup + 1))"
done

rep=1
while [ "$rep" -le "$REPS" ]; do
	if [ "$((rep % 2))" -eq 1 ]; then
		run_proof upstream-to-hxhx sample "$rep" 1
		run_proof hxhx-to-hxhx sample "$rep" 2
	else
		run_proof hxhx-to-hxhx sample "$rep" 1
		run_proof upstream-to-hxhx sample "$rep" 2
	fi
	rep="$((rep + 1))"
done

SOURCE_CLEAN_AT_END=false
if tracked_source_clean; then
	SOURCE_CLEAN_AT_END=true
fi

node "$REPORT_BUILDER" build \
	--results-tsv "$RESULTS_TSV" \
	--reports-dir "$REPORT_DIR" \
	--json-out "$REPORT_JSON" \
	--git-commit "$SOURCE_COMMIT" \
	--start-clean "$SOURCE_CLEAN_AT_START" \
	--end-clean "$SOURCE_CLEAN_AT_END" \
	--reps "$REPS" \
	--warmups "$WARMUPS" \
	--hxhx-bin "$HXHX_BIN_RESOLVED" \
	--hxhx-commit "$HXHX_BIN_COMMIT" \
	--hxhx-provided "$hxhx_provided" \
	--hxhx-preparation-ms "$hxhx_preparation_ms"
node "$REPORT_BUILDER" validate --report "$REPORT_JSON"
node "$REPORT_BUILDER" markdown --report "$REPORT_JSON"
echo "Report: $REPORT_JSON"
echo "HXHX_NATIVE_PLUGIN_LOOP_REPORT:PASS"
