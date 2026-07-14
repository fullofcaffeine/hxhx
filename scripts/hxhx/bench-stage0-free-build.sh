#!/usr/bin/env bash
set -euo pipefail

# Measure a real native hxhx rebuild from the committed OCaml bootstrap
# snapshot. Upstream Haxe is present only for environment provenance and is
# explicitly forbidden from the measured build command.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOURCE_HELPER="$ROOT/scripts/ci/measure-command-resources.py"
REPORT_BUILDER="$ROOT/scripts/ci/stage0-free-build-benchmark-report.js"

REPS="${HXHX_STAGE0_FREE_BUILD_REPS:-3}"
RUN_ID="${HXHX_STAGE0_FREE_BUILD_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
REPORT_DIR="${HXHX_STAGE0_FREE_BUILD_REPORT_DIR:-$ROOT/.artifacts/hxhx/stage0-free-build/$RUN_ID}"
REPORT_JSON="$REPORT_DIR/report.json"
RESULTS_TSV="$REPORT_DIR/results.tsv"
PRIVATE_DUNE_CACHE="$REPORT_DIR/private-dune-cache"
HXHX_DUNE_JOBS_VALUE="${HXHX_DUNE_JOBS:-auto}"
DUNE_CACHE_STORAGE_MODE_VALUE="${HXHX_STAGE0_FREE_BUILD_CACHE_STORAGE_MODE:-auto}"
HAXE_SENTINEL="/definitely-not-used-by-stage0-free-build-benchmark"

fail() {
	echo "stage0-free build benchmark: $*" >&2
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

tracked_source_clean() {
	git -C "$ROOT" diff --quiet --ignore-submodules -- \
		&& git -C "$ROOT" diff --cached --quiet --ignore-submodules --
}

file_sha256() {
	node -e 'const crypto=require("crypto"); const fs=require("fs"); process.stdout.write(crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))' "$1"
}

cache_mode_for_lane() {
	case "$1" in
		cache-disabled)
			printf '%s\n' "disabled"
			;;
		cache-primed)
			printf '%s\n' "enabled-except-user-rules"
			;;
		*)
			fail "unknown build lane: $1"
			;;
	esac
}

require_cmd git
require_cmd haxe
require_cmd node
require_cmd python3
require_cmd dune
require_cmd ocamlc
require_cmd ocamlopt
require_cmd cmp
[ -f "$RESOURCE_HELPER" ] || fail "missing resource helper: $RESOURCE_HELPER"
[ -f "$REPORT_BUILDER" ] || fail "missing report builder: $REPORT_BUILDER"
positive_integer "$REPS" || fail "HXHX_STAGE0_FREE_BUILD_REPS must be a positive integer"
case "$HXHX_DUNE_JOBS_VALUE" in
	auto)
		;;
	''|*[!0-9]*|0)
		fail "HXHX_DUNE_JOBS must be auto or a positive integer"
		;;
esac
case "$DUNE_CACHE_STORAGE_MODE_VALUE" in
	auto|hardlink|copy)
		;;
	*)
		fail "HXHX_STAGE0_FREE_BUILD_CACHE_STORAGE_MODE must be auto, hardlink, or copy"
		;;
esac
[ ! -e "$REPORT_DIR" ] || fail "report directory already exists: $REPORT_DIR"
mkdir -p "$REPORT_DIR/artifacts"

cleanup_private_cache() {
	rm -rf "$PRIVATE_DUNE_CACHE"
}
trap cleanup_private_cache EXIT

SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
SOURCE_CLEAN_AT_START=false
if tracked_source_clean; then
	SOURCE_CLEAN_AT_START=true
fi

printf 'lane\trep\torder\tresource_report\tstdout_log\tstderr_log\tartifact\tsmoke\n' >"$RESULTS_TSV"

run_build() {
	local lane="$1"
	local phase="$2"
	local rep="$3"
	local order="$4"
	local cache_mode
	local run_dir="$REPORT_DIR/runs/${phase}.${rep}.${lane}"
	local build_dir="$run_dir/build"
	local resource_report="$run_dir/resource.json"
	local stdout_log="$run_dir/build.stdout.log"
	local stderr_log="$run_dir/build.stderr.log"
	local smoke_log="$run_dir/targets.stdout.log"
	local artifact_path=""
	local artifact_digest=""
	local retained_artifact=""
	local status=0

	cache_mode="$(cache_mode_for_lane "$lane")"
	mkdir -p "$run_dir"
	set +e
	HAXE_BIN="$HAXE_SENTINEL" \
		HXHX_FORBID_STAGE0=1 \
		HXHX_FORCE_STAGE0=0 \
		HXHX_BOOTSTRAP_PREFER_NATIVE=1 \
		HXHX_STAGE0_OCAML_BUILD=native \
		HXHX_BOOTSTRAP_BUILD_DIR="$build_dir" \
		HXHX_BOOTSTRAP_BUILD_PRUNE=0 \
		HXHX_BOOTSTRAP_HEARTBEAT=0 \
		HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS=0 \
		HXHX_DUNE_JOBS="$HXHX_DUNE_JOBS_VALUE" \
		DUNE_JOBS= \
		DUNE_CACHE="$cache_mode" \
		DUNE_CACHE_ROOT="$PRIVATE_DUNE_CACHE" \
		DUNE_CACHE_STORAGE_MODE="$DUNE_CACHE_STORAGE_MODE_VALUE" \
		python3 "$RESOURCE_HELPER" \
			--cwd "$ROOT" \
			--stdout "$stdout_log" \
			--stderr "$stderr_log" \
			--json-out "$resource_report" \
			--label "${lane}.${rep}" \
			-- bash scripts/hxhx/build-hxhx.sh
	status="$?"
	set -e
	if [ "$status" -ne 0 ]; then
		cat "$stdout_log" >&2 || true
		cat "$stderr_log" >&2 || true
		fail "$phase $lane build failed with exit $status"
	fi

	artifact_path="$(awk 'NF { line=$0 } END { print line }' "$stdout_log")"
	[ -n "$artifact_path" ] || fail "$phase $lane build did not return an artifact path"
	case "$artifact_path" in
		*.exe)
			;;
		*)
			fail "$phase $lane requested native evidence but received $artifact_path"
			;;
	esac
	[ -x "$artifact_path" ] || fail "$phase $lane native artifact is not executable: $artifact_path"
	HAXE_BIN="$HAXE_SENTINEL" HXHX_FORBID_STAGE0=1 "$artifact_path" --hxhx-list-targets >"$smoke_log"
	grep -qx 'js' "$smoke_log" || fail "$phase $lane native artifact smoke did not expose js"
	grep -qx 'ocaml' "$smoke_log" || fail "$phase $lane native artifact smoke did not expose ocaml"

	if [ "$phase" = "prime" ]; then
		echo "prime lane=$lane complete (unrecorded; private cache is now warm)"
		rm -rf "$run_dir"
		return 0
	fi

	artifact_digest="$(file_sha256 "$artifact_path")"
	retained_artifact="$REPORT_DIR/artifacts/hxhx-$artifact_digest.exe"
	if [ -f "$retained_artifact" ]; then
		cmp -s "$artifact_path" "$retained_artifact" || fail "artifact digest collision for $retained_artifact"
	else
		cp "$artifact_path" "$retained_artifact"
		chmod +x "$retained_artifact"
	fi
	rm -rf "$build_dir"
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$lane" "$rep" "$order" "$resource_report" "$stdout_log" "$stderr_log" "$retained_artifact" "$smoke_log" >>"$RESULTS_TSV"
	local elapsed_ms peak_rss_kb
	elapsed_ms="$(node -e 'const r=require(process.argv[1]); process.stdout.write(String(r.elapsed_ms))' "$resource_report")"
	peak_rss_kb="$(node -e 'const r=require(process.argv[1]); process.stdout.write(String(r.peak_child_rss_kb))' "$resource_report")"
	echo "sample lane=$lane #$rep order=$order build=${elapsed_ms}ms child_peak_rss=${peak_rss_kb}KiB"
}

echo "== Stage0-free native hxhx build benchmark"
echo "Commit: $SOURCE_COMMIT"
echo "Repetitions per lane: $REPS"
echo "Dune jobs: $HXHX_DUNE_JOBS_VALUE"
echo "Dune cache storage mode: $DUNE_CACHE_STORAGE_MODE_VALUE"
echo "Report directory: $REPORT_DIR"
echo ""

run_build cache-primed prime 0 0

rep=1
while [ "$rep" -le "$REPS" ]; do
	if [ "$((rep % 2))" -eq 1 ]; then
		run_build cache-disabled sample "$rep" 1
		run_build cache-primed sample "$rep" 2
	else
		run_build cache-primed sample "$rep" 1
		run_build cache-disabled sample "$rep" 2
	fi
	rep="$((rep + 1))"
done

# The private cache is a measurement input, not evidence to upload. The
# retained native artifacts, logs, and resource records remain in REPORT_DIR.
rm -rf "$PRIVATE_DUNE_CACHE"

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
	--dune-jobs "$HXHX_DUNE_JOBS_VALUE" \
	--cache-storage-mode "$DUNE_CACHE_STORAGE_MODE_VALUE" \
	--cache-prime-completed true
node "$REPORT_BUILDER" validate --report "$REPORT_JSON"
node "$REPORT_BUILDER" markdown --report "$REPORT_JSON"
echo "Report: $REPORT_JSON"
echo "HXHX_STAGE0_FREE_BUILD_REPORT:PASS"
