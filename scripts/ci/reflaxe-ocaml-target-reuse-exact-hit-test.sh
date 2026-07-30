#!/usr/bin/env bash
set -euo pipefail

# Proves that the real standalone OCaml target admits one successful miss and
# then skips its complete miss-only preparation on an exact server request.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_TEMPLATE="$ROOT/test/reflaxe_ocaml_target_reuse_exact"
SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
MATRIX_HELPER="$ROOT/scripts/ci/reflaxe-ocaml-server-matrix-helper.js"
WORK_DIR="$(mktemp -d "$ROOT/.reflaxe-ocaml-target-reuse-exact.XXXXXX")"
PROJECT_DIR="$WORK_DIR/project"
STATE_DIR="$WORK_DIR/server-state"
TEST_SENTINEL_DIR="$WORK_DIR/test-sentinels"
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
		"${HAXE_BIN:-haxe}" \
			--connect "$SERVER_PORT" \
			build.hxml \
			-D "ocaml_output=$OUTPUT_NAME" \
			-D ocaml_build=native \
			-D reflaxe_output_transaction \
			-D reflaxe_ocaml_target_reuse \
			-D reflaxe_ocaml_target_reuse_test_require_hit \
			-D reflaxe.dont_output_metadata_id \
			"$@"
	)
}

compile_expected_hit() {
	mkdir -p "$TEST_SENTINEL_DIR"
	touch "$TEST_SENTINEL_DIR/expect-hit"
	if ! compile_server "$@"; then
		if [[ -f "$TEST_SENTINEL_DIR/catalog-events.tsv" ]]; then
			sed -n '1,240p' "$TEST_SENTINEL_DIR/catalog-events.tsv" >&2
		fi
		return 1
	fi
	if [[ ! -f "$TEST_SENTINEL_DIR/expect-hit" ]]; then
		echo "reflaxe.ocaml expected-hit marker was consumed by miss-only preparation" >&2
		exit 1
	fi
	rm "$TEST_SENTINEL_DIR/expect-hit"
}

compile_expected_miss() {
	mkdir -p "$TEST_SENTINEL_DIR"
	touch "$TEST_SENTINEL_DIR/expect-miss"
	if ! compile_server "$@"; then
		if [[ -f "$TEST_SENTINEL_DIR/catalog-events.tsv" ]]; then
			sed -n '1,240p' "$TEST_SENTINEL_DIR/catalog-events.tsv" >&2
		fi
		return 1
	fi
	if [[ ! -f "$TEST_SENTINEL_DIR/expect-miss" ]]; then
		echo "reflaxe.ocaml expected-miss marker was consumed by an unexpected replay" >&2
		exit 1
	fi
	rm "$TEST_SENTINEL_DIR/expect-miss"
}

mkdir -p "$STATE_DIR"
cp -R "$FIXTURE_TEMPLATE" "$PROJECT_DIR"

start_server() {
	REFLAXE_OCAML_REUSE_TEST_SENTINEL_DIR="$TEST_SENTINEL_DIR" \
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

start_server

compile_server
first_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
first_revision="$(node "$MATRIX_HELPER" source-bundle-revision "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json")"
first_executable="$(current_executable)"
first_executable_digest="$(shasum -a 256 "$first_executable" | awk '{print $1}')"
compile_expected_hit
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

node "$MATRIX_HELPER" replace "$PROJECT_DIR/src/ReuseFixtureMacro.hx" '"resource-a"' '"resource-b"'
compile_expected_miss
resource_b_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
assert_runtime "exact target replay"
compile_expected_hit
if [[ "$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")" != "$resource_b_digest" ]]; then
	echo "reflaxe.ocaml generated-resource exact hit changed the complete output" >&2
	exit 1
fi
node "$MATRIX_HELPER" replace "$PROJECT_DIR/src/ReuseFixtureMacro.hx" '"resource-b"' '"resource-a"'
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
