#!/usr/bin/env bash
set -euo pipefail

# Proves that the real standalone OCaml target admits one successful miss and
# then skips its complete miss-only preparation on an exact server request.
MODE="${1:-semantic}"
if [[ "$MODE" != "semantic" && "$MODE" != "memory" && "$MODE" != "memory-control" && "$MODE" != "memory-gc" ]]; then
	echo "usage: $0 [semantic|memory|memory-control|memory-gc]" >&2
	exit 2
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_TEMPLATE="$ROOT/test/reflaxe_ocaml_target_reuse_exact"
SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
MATRIX_HELPER="$ROOT/scripts/ci/reflaxe-ocaml-server-matrix-helper.js"
WORK_DIR="$(mktemp -d "$ROOT/.reflaxe-ocaml-target-reuse-exact.XXXXXX")"
PROJECT_DIR="$WORK_DIR/project"
STATE_DIR="$WORK_DIR/server-state"
TEST_SENTINEL_DIR="$WORK_DIR/test-sentinels"
PHASE_REPORT_DIR="$WORK_DIR/phase-reports"
RESOURCE_INPUT="$PROJECT_DIR/reuse-resource.txt"
OUTPUT_NAME="out_exact_hit_$$"
SERVER_PORT="${REFLAXE_OCAML_EXACT_HIT_PORT:-$((25000 + ($$ % 10000)))}"
SERVER_STARTED=0

cleanup() {
	if [[ "$SERVER_STARTED" = "1" ]]; then
		HXHX_STATE_DIR="$STATE_DIR" \
			HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
			HAXE_BIN="${HAXE_BIN:-haxe}" \
			bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true
	fi
	if [[ -d "$WORK_DIR" ]]; then
		find "$WORK_DIR" -depth -delete
	fi
}
trap cleanup EXIT

compile_server() {
	(
		cd "$PROJECT_DIR"
		local arguments=(
			--connect "$SERVER_PORT" \
			build.hxml \
			-D "ocaml_output=$OUTPUT_NAME" \
			-D ocaml_build=native \
			-D reflaxe_output_transaction \
			-D reflaxe_ocaml_target_reuse \
			-D reflaxe_ocaml_target_reuse_test_require_hit \
			-D reflaxe.dont_output_metadata_id
		)
		if [[ "$MODE" = "memory-gc" ]]; then
			arguments+=(-D reflaxe_ocaml_target_reuse_test_force_gc)
		fi
		arguments+=("$@")
		"${HAXE_BIN:-haxe}" "${arguments[@]}"
	)
}

compile_server_emit_only() {
	(
		cd "$PROJECT_DIR"
		local arguments=(
			--connect "$SERVER_PORT" \
			build.hxml \
			-D "ocaml_output=$OUTPUT_NAME" \
			-D ocaml_no_build \
			-D reflaxe_output_transaction \
			-D reflaxe_ocaml_target_reuse \
			-D reflaxe_ocaml_target_reuse_test_require_hit \
			-D reflaxe.dont_output_metadata_id
		)
		if [[ "$MODE" = "memory-gc" ]]; then
			arguments+=(-D reflaxe_ocaml_target_reuse_test_force_gc)
		fi
		arguments+=("$@")
		"${HAXE_BIN:-haxe}" "${arguments[@]}"
	)
}

compile_server_memory_control() {
	(
		cd "$PROJECT_DIR"
		local arguments=(
			--connect "$SERVER_PORT" \
			build.hxml \
			-D "ocaml_output=$OUTPUT_NAME" \
			-D ocaml_no_build \
			-D reflaxe_output_transaction \
			-D reflaxe.dont_output_metadata_id
		)
		if [[ "$MODE" = "memory-gc" ]]; then
			arguments+=(-D reflaxe_ocaml_target_reuse_test_force_gc)
		fi
		arguments+=("$@")
		"${HAXE_BIN:-haxe}" "${arguments[@]}"
	)
}

compile_with_expectation() {
	local expectation="$1"
	local runner="$2"
	shift 2
	local marker="$TEST_SENTINEL_DIR/expect-$expectation"
	mkdir -p "$TEST_SENTINEL_DIR"
	touch "$marker"
	if ! "$runner" "$@"; then
		if [[ -f "$TEST_SENTINEL_DIR/catalog-events.tsv" ]]; then
			sed -n '1,240p' "$TEST_SENTINEL_DIR/catalog-events.tsv" >&2
		fi
		return 1
	fi
	if [[ ! -f "$marker" ]]; then
		echo "reflaxe.ocaml expected-$expectation marker was consumed by the wrong target path" >&2
		exit 1
	fi
	rm "$marker"
}

compile_expected_hit() {
	compile_with_expectation hit compile_server "$@"
}

compile_expected_miss() {
	compile_with_expectation miss compile_server "$@"
}

compile_expected_hit_emit_only() {
	compile_with_expectation hit compile_server_emit_only "$@"
}

compile_expected_miss_emit_only() {
	compile_with_expectation miss compile_server_emit_only "$@"
}

mkdir -p "$STATE_DIR" "$PHASE_REPORT_DIR"
cp -R "$FIXTURE_TEMPLATE" "$PROJECT_DIR"

start_server() {
	REFLAXE_OCAML_REUSE_TEST_SENTINEL_DIR="$TEST_SENTINEL_DIR" \
		REFLAXE_OCAML_TARGET_REUSE_PHASE_REPORT_DIR="$PHASE_REPORT_DIR" \
		HXHX_STATE_DIR="$STATE_DIR" \
		HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
		HAXE_BIN="${HAXE_BIN:-haxe}" \
		bash "$SERVER_HELPER" start
	SERVER_STARTED=1
}

stop_server() {
	HXHX_STATE_DIR="$STATE_DIR" \
		HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
		HAXE_BIN="${HAXE_BIN:-haxe}" \
		bash "$SERVER_HELPER" stop
	SERVER_STARTED=0
}

reset_generated_state() {
	if [[ -d "$PROJECT_DIR/$OUTPUT_NAME" ]]; then
		find "$PROJECT_DIR/$OUTPUT_NAME" -depth -delete
	fi
	if [[ -d "$PROJECT_DIR/.$OUTPUT_NAME.reflaxe-ocaml-dune-build" ]]; then
		find "$PROJECT_DIR/.$OUTPUT_NAME.reflaxe-ocaml-dune-build" -depth -delete
	fi
}

current_executable() {
	find "$PROJECT_DIR/.$OUTPUT_NAME.reflaxe-ocaml-dune-build" -type f -name "$OUTPUT_NAME.exe" -print -quit
}

assert_runtime() {
	local expected="$1"
	local executable
	executable="$(current_executable)"
	if [[ -z "$executable" || ! -x "$executable" ]]; then
		echo "reflaxe.ocaml exact target replay did not preserve the native executable" >&2
		exit 1
	fi
	local actual
	actual="$("$executable")"
	if [[ "$actual" != "$expected" ]]; then
		echo "reflaxe.ocaml exact target replay changed native runtime behavior: expected '$expected', got '$actual'" >&2
		exit 1
	fi
}

server_rss_kb() {
	local total=0
	local rss
	local pid
	while IFS= read -r pid; do
		[[ "$pid" =~ ^[0-9]+$ ]] || continue
		rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
		if [[ "$rss" =~ ^[0-9]+$ ]]; then
			total="$((total + rss))"
		fi
	done < <(
		HXHX_STATE_DIR="$STATE_DIR" \
			HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
			HAXE_BIN="${HAXE_BIN:-haxe}" \
			bash "$SERVER_HELPER" owned-pids
	)
	printf '%s\n' "$total"
}

run_memory_gate() {
	start_server
	compile_server_emit_only
	compile_expected_hit_emit_only
	local gc_baseline_line=""
	if [[ "$MODE" = "memory-gc" ]]; then
		gc_baseline_line="$(tail -n 1 "$TEST_SENTINEL_DIR/gc-events.tsv")"
	fi
	local stable_revision
	stable_revision="$(node "$MATRIX_HELPER" source-bundle-revision "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json")"
	local rss_baseline_kb
	local rss_after_10_kb=0
	local rss_after_20_kb=0
	local rss_peak_kb
	local current_rss_kb
	rss_baseline_kb="$(server_rss_kb)"
	rss_peak_kb="$rss_baseline_kb"
	for request in {1..30}; do
		compile_expected_hit_emit_only
		if [[ "$(node "$MATRIX_HELPER" source-bundle-revision "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json")" != "$stable_revision" ]]; then
			echo "reflaxe.ocaml repeated exact hit $request changed the source-bundle revision" >&2
			exit 1
		fi
		current_rss_kb="$(server_rss_kb)"
		if (( current_rss_kb > rss_peak_kb )); then
			rss_peak_kb="$current_rss_kb"
		fi
		if (( request == 10 )); then
			rss_after_10_kb="$current_rss_kb"
		elif (( request == 20 )); then
			rss_after_20_kb="$current_rss_kb"
		fi
	done
	local rss_after_30_kb
	rss_after_30_kb="$(server_rss_kb)"
	local gc_after_30_line=""
	if [[ "$MODE" = "memory-gc" ]]; then
		gc_after_30_line="$(tail -n 1 "$TEST_SENTINEL_DIR/gc-events.tsv")"
	fi
	if (( rss_after_30_kb > rss_baseline_kb + 131072 )); then
		echo "reflaxe.ocaml thirty exact hits grew server RSS by more than 128 MiB (baseline=${rss_baseline_kb}KB after10=${rss_after_10_kb}KB after20=${rss_after_20_kb}KB after30=${rss_after_30_kb}KB peak=${rss_peak_kb}KB)" >&2
		exit 1
	fi
	if (( rss_after_30_kb > rss_after_20_kb + 32768 )); then
		echo "reflaxe.ocaml exact-hit RSS did not approach a plateau in the final ten requests (after20=${rss_after_20_kb}KB after30=${rss_after_30_kb}KB)" >&2
		exit 1
	fi

	local current_resource="resource-a"
	local next_resource
	for variant in {1..8}; do
		next_resource="resource-churn-$variant"
		node "$MATRIX_HELPER" replace "$RESOURCE_INPUT" "$current_resource" "$next_resource"
		compile_expected_miss_emit_only
		compile_expected_hit_emit_only
		current_resource="$next_resource"
		current_rss_kb="$(server_rss_kb)"
		if (( current_rss_kb > rss_peak_kb )); then
			rss_peak_kb="$current_rss_kb"
		fi
	done
	node "$MATRIX_HELPER" replace "$RESOURCE_INPUT" "$current_resource" "resource-a"
	compile_expected_hit_emit_only

	local catalog_line
	local catalog_payload_bytes
	local catalog_overhead_bytes
	local catalog_budget_bytes
	catalog_line="$(tail -n 1 "$TEST_SENTINEL_DIR/catalog-events.tsv")"
	catalog_payload_bytes="$(printf '%s\n' "$catalog_line" | awk -F '\t' '{print $8}')"
	catalog_overhead_bytes="$(printf '%s\n' "$catalog_line" | awk -F '\t' '{print $9}')"
	catalog_budget_bytes="$(printf '%s\n' "$catalog_line" | awk -F '\t' '{print $10}')"
	if (( catalog_payload_bytes + catalog_overhead_bytes > catalog_budget_bytes )); then
		echo "reflaxe.ocaml multi-entry churn exceeded the catalog hard budget" >&2
		exit 1
	fi

	local rss_before_final_10_kb
	rss_before_final_10_kb="$(server_rss_kb)"
	local gc_before_final_10_line=""
	if [[ "$MODE" = "memory-gc" ]]; then
		gc_before_final_10_line="$(tail -n 1 "$TEST_SENTINEL_DIR/gc-events.tsv")"
	fi
	for _ in {1..10}; do
		compile_expected_hit_emit_only
	done
	local rss_final_kb
	rss_final_kb="$(server_rss_kb)"
	local gc_final_line=""
	if [[ "$MODE" = "memory-gc" ]]; then
		gc_final_line="$(tail -n 1 "$TEST_SENTINEL_DIR/gc-events.tsv")"
	fi
	if (( rss_final_kb > rss_before_final_10_kb + 32768 )); then
		echo "reflaxe.ocaml post-churn exact hits did not approach an RSS plateau" >&2
		exit 1
	fi
	if (( rss_final_kb > rss_baseline_kb + 131072 )); then
		echo "reflaxe.ocaml exact-hit and churn sequence grew server RSS by more than 128 MiB (baseline=${rss_baseline_kb}KB after30=${rss_after_30_kb}KB beforeFinal10=${rss_before_final_10_kb}KB final=${rss_final_kb}KB catalogPayload=${catalog_payload_bytes}B catalogOverhead=${catalog_overhead_bytes}B)" >&2
		exit 1
	fi

	local catalog_event_count
	local reset_lookup_line
	catalog_event_count="$(wc -l <"$TEST_SENTINEL_DIR/catalog-events.tsv" | tr -d ' ')"
	compile_expected_miss_emit_only --macro 'ReuseTargetCatalogControl.reset("exact-memory-fixture")'
	reset_lookup_line="$(sed -n "$((catalog_event_count + 1))p" "$TEST_SENTINEL_DIR/catalog-events.tsv")"
	if [[ "$(printf '%s\n' "$reset_lookup_line" | awk -F '\t' '{print $1}')" != "lookup" \
		|| "$(printf '%s\n' "$reset_lookup_line" | awk -F '\t' '{print $5}')" != "0" \
		|| "$(printf '%s\n' "$reset_lookup_line" | awk -F '\t' '{print $8}')" != "0" \
		|| "$(printf '%s\n' "$reset_lookup_line" | awk -F '\t' '{print $12}')" != "0" ]]; then
		echo "reflaxe.ocaml explicit reset did not clear entries, payload bytes, and leases before lookup: $reset_lookup_line" >&2
		exit 1
	fi
	compile_expected_hit_emit_only

	if [[ "$MODE" = "memory-gc" ]]; then
		local word_bytes
		local gc_baseline_heap_words
		local gc_baseline_live_words
		local gc_after_30_heap_words
		local gc_after_30_live_words
		local gc_before_final_10_live_words
		local gc_final_heap_words
		local gc_final_live_words
		local gc_final_top_heap_words
		word_bytes="$(( $(getconf LONG_BIT) / 8 ))"
		gc_baseline_heap_words="$(printf '%s\n' "$gc_baseline_line" | awk -F '\t' '{print $7}')"
		gc_baseline_live_words="$(printf '%s\n' "$gc_baseline_line" | awk -F '\t' '{print $8}')"
		gc_after_30_heap_words="$(printf '%s\n' "$gc_after_30_line" | awk -F '\t' '{print $7}')"
		gc_after_30_live_words="$(printf '%s\n' "$gc_after_30_line" | awk -F '\t' '{print $8}')"
		gc_before_final_10_live_words="$(printf '%s\n' "$gc_before_final_10_line" | awk -F '\t' '{print $8}')"
		gc_final_heap_words="$(printf '%s\n' "$gc_final_line" | awk -F '\t' '{print $7}')"
		gc_final_live_words="$(printf '%s\n' "$gc_final_line" | awk -F '\t' '{print $8}')"
		gc_final_top_heap_words="$(printf '%s\n' "$gc_final_line" | awk -F '\t' '{print $12}')"
		if (( (gc_after_30_live_words - gc_baseline_live_words) * word_bytes > 33554432 )); then
			echo "reflaxe.ocaml thirty exact hits retained more than 32 MiB of compacted live heap" >&2
			exit 1
		fi
		if (( (gc_final_live_words - gc_before_final_10_live_words) * word_bytes > 33554432 )); then
			echo "reflaxe.ocaml final ten exact hits retained more than 32 MiB of compacted live heap" >&2
			exit 1
		fi
		if (( (gc_final_live_words - gc_baseline_live_words) * word_bytes > catalog_payload_bytes + catalog_overhead_bytes + 33554432 )); then
			echo "reflaxe.ocaml compacted live heap exceeded catalog bytes plus bounded request overhead" >&2
			exit 1
		fi
		echo "REFLAXE_OCAML_TARGET_REUSE_MEMORY_GC_DIAGNOSTIC:PASS baseline_heap_words=$gc_baseline_heap_words baseline_live_words=$gc_baseline_live_words after30_heap_words=$gc_after_30_heap_words after30_live_words=$gc_after_30_live_words final_heap_words=$gc_final_heap_words final_live_words=$gc_final_live_words top_heap_words=$gc_final_top_heap_words word_bytes=$word_bytes"
	fi

	if [[ "$MODE" = "memory-gc" ]]; then
		echo "REFLAXE_OCAML_TARGET_REUSE_MEMORY_COMPACTED_RSS:PASS baseline_kb=$rss_baseline_kb after10_kb=$rss_after_10_kb after20_kb=$rss_after_20_kb after30_kb=$rss_after_30_kb peak_kb=$rss_peak_kb final_kb=$rss_final_kb catalog_payload_bytes=$catalog_payload_bytes catalog_overhead_bytes=$catalog_overhead_bytes catalog_budget_bytes=$catalog_budget_bytes"
	else
		echo "REFLAXE_OCAML_TARGET_REUSE_MEMORY:PASS baseline_kb=$rss_baseline_kb after10_kb=$rss_after_10_kb after20_kb=$rss_after_20_kb after30_kb=$rss_after_30_kb peak_kb=$rss_peak_kb final_kb=$rss_final_kb catalog_payload_bytes=$catalog_payload_bytes catalog_overhead_bytes=$catalog_overhead_bytes catalog_budget_bytes=$catalog_budget_bytes"
	fi
}

run_memory_control() {
	start_server
	compile_server_memory_control
	local stable_revision
	stable_revision="$(node "$MATRIX_HELPER" source-bundle-revision "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json")"
	local rss_baseline_kb
	local rss_after_10_kb=0
	local rss_after_20_kb=0
	local rss_peak_kb
	local current_rss_kb
	rss_baseline_kb="$(server_rss_kb)"
	rss_peak_kb="$rss_baseline_kb"
	for request in {1..30}; do
		compile_server_memory_control
		if [[ "$(node "$MATRIX_HELPER" source-bundle-revision "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json")" != "$stable_revision" ]]; then
			echo "reflaxe.ocaml memory control request $request changed the source-bundle revision" >&2
			exit 1
		fi
		current_rss_kb="$(server_rss_kb)"
		if (( current_rss_kb > rss_peak_kb )); then
			rss_peak_kb="$current_rss_kb"
		fi
		if (( request == 10 )); then
			rss_after_10_kb="$current_rss_kb"
		elif (( request == 20 )); then
			rss_after_20_kb="$current_rss_kb"
		fi
	done
	local rss_final_kb
	rss_final_kb="$(server_rss_kb)"
	echo "REFLAXE_OCAML_TARGET_REUSE_MEMORY_CONTROL:PASS baseline_kb=$rss_baseline_kb after10_kb=$rss_after_10_kb after20_kb=$rss_after_20_kb final_kb=$rss_final_kb peak_kb=$rss_peak_kb"
}

if [[ "$MODE" = "memory" || "$MODE" = "memory-gc" ]]; then
	run_memory_gate
	exit 0
fi
if [[ "$MODE" = "memory-control" ]]; then
	run_memory_control
	exit 0
fi

start_server

compile_server
first_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
first_revision="$(node "$MATRIX_HELPER" source-bundle-revision "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json")"
first_executable="$(current_executable)"
first_executable_digest="$(shasum -a 256 "$first_executable" | awk '{print $1}')"
compile_expected_hit
node "$MATRIX_HELPER" verify-reuse-phase-pair \
	"$PHASE_REPORT_DIR/request-000001.json" \
	"$PHASE_REPORT_DIR/request-000002.json"
second_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
second_executable="$(current_executable)"
second_executable_digest="$(shasum -a 256 "$second_executable" | awk '{print $1}')"

if [[ "$first_digest" != "$second_digest" ]]; then
	echo "reflaxe.ocaml exact target replay changed the complete generated tree" >&2
	exit 1
fi
if [[ "$first_executable_digest" != "$second_executable_digest" ]]; then
	echo "reflaxe.ocaml exact target replay changed the native executable digest" >&2
	exit 1
fi
assert_runtime "exact target replay"

if [[ "$("${HAXE_BIN:-haxe}" -version)" == 4.* ]]; then
	node "$MATRIX_HELPER" replace "$PROJECT_DIR/src/Main.hx" 'class Main {' $'@:rtti\nclass Main {'
	compile_expected_miss
	compile_expected_miss
	node "$MATRIX_HELPER" verify-rtti-ineligible-phase-pair \
		"$PHASE_REPORT_DIR/request-000002.json" \
		"$PHASE_REPORT_DIR/request-000003.json" \
		"$PHASE_REPORT_DIR/request-000004.json"
	assert_runtime "exact target replay"
	node "$MATRIX_HELPER" replace "$PROJECT_DIR/src/Main.hx" $'@:rtti\nclass Main {' 'class Main {'
	compile_expected_hit
	if [[ "$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")" != "$first_digest" ]]; then
		echo "reflaxe.ocaml did not recover the original exact-hit result after the RTTI safety probe" >&2
		exit 1
	fi
fi

node "$MATRIX_HELPER" replace "$PROJECT_DIR/src/Main.hx" 'Sys.println("exact target replay");' 'Sys.println("edited exact target replay");'
compile_expected_miss
edited_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
edited_revision="$(node "$MATRIX_HELPER" source-bundle-revision "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json")"
if [[ "$edited_digest" = "$first_digest" || "$edited_revision" = "$first_revision" ]]; then
	echo "reflaxe.ocaml source edit did not invalidate exact target reuse" >&2
	exit 1
fi
assert_runtime "edited exact target replay"
compile_expected_hit
edited_hit_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
if [[ "$edited_hit_digest" != "$edited_digest" ]]; then
	echo "reflaxe.ocaml edited exact hit changed the complete generated tree" >&2
	exit 1
fi

node "$MATRIX_HELPER" replace "$PROJECT_DIR/src/Main.hx" 'Sys.println("edited exact target replay");' 'Sys.println("exact target replay");'
compile_expected_hit
restored_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
restored_revision="$(node "$MATRIX_HELPER" source-bundle-revision "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json")"
if [[ "$restored_digest" != "$first_digest" || "$restored_revision" != "$first_revision" ]]; then
	echo "reflaxe.ocaml A-to-B-to-A replay did not restore the original source result" >&2
	exit 1
fi
assert_runtime "exact target replay"

compile_expected_miss -D exact_reuse_config=one
compile_expected_hit -D exact_reuse_config=one
compile_expected_miss -D exact_reuse_config=two
compile_expected_hit -D exact_reuse_config=two
compile_expected_miss

node "$MATRIX_HELPER" replace "$RESOURCE_INPUT" "resource-a" "resource-b"
compile_expected_miss
resource_b_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
assert_runtime "exact target replay"
compile_expected_hit
if [[ "$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")" != "$resource_b_digest" ]]; then
	echo "reflaxe.ocaml generated-resource exact hit changed the complete output" >&2
	exit 1
fi
node "$MATRIX_HELPER" replace "$RESOURCE_INPUT" "resource-b" "resource-a"
compile_expected_hit
if [[ "$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")" != "$first_digest" ]]; then
	echo "reflaxe.ocaml restored generated resource did not recover the original source result" >&2
	exit 1
fi

compile_expected_miss -D ocaml_sourcemap
sourcemap_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
compile_expected_hit -D ocaml_sourcemap
node "$MATRIX_HELPER" replace "$PROJECT_DIR/src/Main.hx" $'\t\tSys.println' $'\n\t\tSys.println'
compile_expected_miss -D ocaml_sourcemap
sourcemap_edited_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
if [[ "$sourcemap_edited_digest" = "$sourcemap_digest" ]]; then
	echo "reflaxe.ocaml source-map newline edit did not invalidate exact target reuse" >&2
	exit 1
fi
compile_expected_hit -D ocaml_sourcemap
node "$MATRIX_HELPER" replace "$PROJECT_DIR/src/Main.hx" $'\n\t\tSys.println' $'\t\tSys.println'
compile_expected_hit -D ocaml_sourcemap
if [[ "$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")" != "$sourcemap_digest" ]]; then
	echo "reflaxe.ocaml restored source-map input did not recover the original result" >&2
	exit 1
fi
compile_expected_miss
compile_expected_hit

stop_server
reset_generated_state
start_server
compile_server -D reflaxe_ocaml_target_reuse_test_corrupt_first_admission
corrupt_baseline_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
compile_expected_miss -D reflaxe_ocaml_target_reuse_test_corrupt_first_admission
compile_expected_hit -D reflaxe_ocaml_target_reuse_test_corrupt_first_admission
if [[ "$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")" != "$corrupt_baseline_digest" ]]; then
	echo "reflaxe.ocaml corrupt-payload fallback changed the generated result" >&2
	exit 1
fi

stop_server
reset_generated_state
start_server
if compile_server -D reflaxe_ocaml_target_reuse_test_fail_once_after_stage; then
	echo "reflaxe.ocaml staged-candidate failure injection unexpectedly succeeded" >&2
	exit 1
fi
if [[ -e "$PROJECT_DIR/$OUTPUT_NAME" ]]; then
	echo "reflaxe.ocaml staged-candidate failure published generated source" >&2
	exit 1
fi
compile_expected_miss -D reflaxe_ocaml_target_reuse_test_fail_once_after_stage
compile_expected_hit -D reflaxe_ocaml_target_reuse_test_fail_once_after_stage

stop_server
reset_generated_state
start_server
if compile_server -D reflaxe_ocaml_target_reuse_test_fail_once_after_published_work; then
	echo "reflaxe.ocaml post-publication failure injection unexpectedly succeeded" >&2
	exit 1
fi
if [[ ! -f "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json" ]]; then
	echo "reflaxe.ocaml post-publication failure did not preserve the documented public source tree" >&2
	exit 1
fi
compile_expected_miss -D reflaxe_ocaml_target_reuse_test_fail_once_after_published_work
compile_expected_hit -D reflaxe_ocaml_target_reuse_test_fail_once_after_published_work

echo "REFLAXE_OCAML_TARGET_REUSE_EXACT_HIT:PASS digest=$restored_digest"
