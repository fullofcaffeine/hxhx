#!/usr/bin/env bash
set -euo pipefail

# Proves the practical warm-server contract through the real standalone OCaml
# target. Haxe may reuse unchanged frontend modules, but every Reflaxe request
# must still receive one complete current program and publish one complete
# generated tree.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$ROOT/test/reflaxe_ocaml_complete_program_server"
SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
MATRIX_HELPER="$ROOT/scripts/ci/reflaxe-ocaml-server-matrix-helper.js"
HAXE_BIN="${HAXE_BIN:-haxe}"
HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "reflaxe.ocaml complete-program server test: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
	exit 1
fi

WORK_DIR="$(mktemp -d "$ROOT/.reflaxe-ocaml-complete-program-server.XXXXXX")"
PROJECT_DIR="$WORK_DIR/project"
SNAPSHOT_DIR="$WORK_DIR/snapshots"
SERVER_STATE_DIR="$WORK_DIR/server-state"
SERVER_PORT="${REFLAXE_OCAML_TEST_SERVER_PORT:-$((24000 + ($$ % 10000)))}"
BUILD_DIR="$PROJECT_DIR/.out.reflaxe-ocaml-dune-build"
MAIN_SOURCE="$PROJECT_DIR/src/Main.hx"
MESSAGE_SOURCE="$PROJECT_DIR/src/Message.hx"
API_SOURCE="$PROJECT_DIR/src/Api.hx"
MACRO_SOURCE="$PROJECT_DIR/src/BuildMacro.hx"
BUILD_HXML="$PROJECT_DIR/build.hxml"
SERVER_STARTED=0

cleanup() {
	if [[ "$SERVER_STARTED" = "1" ]]; then
		HXHX_STATE_DIR="$SERVER_STATE_DIR" \
			HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
			HAXE_BIN="$HAXE_BIN" \
			bash "$SERVER_HELPER" stop >/dev/null 2>&1 || true
	fi
	if [[ -d "$WORK_DIR" ]]; then
		find "$WORK_DIR" -depth -delete
	fi
}
trap cleanup EXIT

fail() {
	echo "reflaxe.ocaml complete-program server test: $*" >&2
	exit 1
}

milliseconds() {
	node -e 'process.stdout.write(String(Date.now()))'
}

replace_source_text() {
	node "$MATRIX_HELPER" replace "$1" "$2" "$3"
}

program_revision() {
	node "$MATRIX_HELPER" program-revision "$1/ocaml_artifact_manifest.json"
}

tree_digest() {
	node "$MATRIX_HELPER" tree-digest "$1"
}

clear_output() {
	if [[ -d "$PROJECT_DIR/out" ]]; then
		find "$PROJECT_DIR/out" -depth -delete
	fi
}

compile_clean() {
	(
		cd "$PROJECT_DIR"
		"$HAXE_BIN" \
			-D reflaxe_output_transaction \
			-D ocaml_no_build \
			-D reflaxe.dont_output_metadata_id \
			"$@" \
			build.hxml
	)
}

compile_server() {
	(
		cd "$PROJECT_DIR"
		"$HAXE_BIN" \
			-D reflaxe_output_transaction \
			-D ocaml_no_build \
			-D reflaxe.dont_output_metadata_id \
			--connect "$SERVER_PORT" \
			"$@" \
			build.hxml
	)
}

compile_server_with_transaction_failure() {
	compile_server -D reflaxe_output_transaction_test_fail_before_commit "$@"
}

start_server() {
	if "$HAXE_BIN" --connect "$SERVER_PORT" --version >/dev/null 2>&1; then
		fail "chosen compiler-server port $SERVER_PORT is already in use"
	fi
	HXHX_STATE_DIR="$SERVER_STATE_DIR" \
		HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
		HAXE_BIN="$HAXE_BIN" \
		bash "$SERVER_HELPER" start
	SERVER_STARTED=1
}

stop_server() {
	HXHX_STATE_DIR="$SERVER_STATE_DIR" \
		HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
		HAXE_BIN="$HAXE_BIN" \
		bash "$SERVER_HELPER" stop
	SERVER_STARTED=0
	if HXHX_STATE_DIR="$SERVER_STATE_DIR" \
		HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
		HAXE_BIN="$HAXE_BIN" \
		bash "$SERVER_HELPER" owned-pids | grep -q '[0-9]'; then
		fail "the owned compiler server still reports a live process after shutdown"
	fi
}

assert_no_private_state() {
	if find "$PROJECT_DIR" -maxdepth 1 -type d -name '.*.reflaxe-output-*' -print -quit | grep -q .; then
		fail "a completed request left private output transaction state"
	fi
	if grep -R -a -F '.reflaxe-output-transaction' "$PROJECT_DIR/out" "$BUILD_DIR" >/dev/null 2>&1; then
		fail "a private transaction path entered generated output or Dune metadata"
	fi
}

snapshot_output() {
	local name="$1"
	local destination="$SNAPSHOT_DIR/$name"
	[[ -f "$PROJECT_DIR/out/ocaml_artifact_manifest.json" ]] \
		|| fail "request '$name' did not publish the artifact manifest"
	[[ -f "$PROJECT_DIR/out/_GeneratedFiles.json" ]] \
		|| fail "request '$name' did not publish the complete generated-file receipt"
	assert_no_private_state
	mkdir -p "$destination"
	cp -R "$PROJECT_DIR/out/." "$destination/"
}

compare_snapshots() {
	local expected="$1"
	local actual="$2"
	diff -ru "$SNAPSHOT_DIR/$expected" "$SNAPSHOT_DIR/$actual" \
		|| fail "generated target trees differ: expected '$expected', got '$actual'"
}

run_published() {
	local name="$1"
	local expected="$2"
	local actual="$WORK_DIR/runtime-$name.stdout"
	local expected_file="$WORK_DIR/runtime-$name.expected"
	local dune_log="$WORK_DIR/runtime-$name.dune.log"
	if ! dune build --root "$PROJECT_DIR/out" --build-dir "$BUILD_DIR" ./out.exe >"$dune_log" 2>&1; then
		sed -n '1,240p' "$dune_log" >&2
		fail "Dune could not build published state '$name'"
	fi
	"$BUILD_DIR/default/out.exe" >"$actual"
	printf '%s\n' "$expected" >"$expected_file"
	diff -u "$expected_file" "$actual" \
		|| fail "native behavior differs for state '$name'"
}

compile_and_verify_state() {
	local name="$1"
	local expected="$2"
	shift 2

	local server_started_at
	local server_elapsed
	server_started_at="$(milliseconds)"
	compile_server "$@"
	server_elapsed="$(( $(milliseconds) - server_started_at ))"
	snapshot_output "warm-$name"
	run_published "warm-$name" "$expected"
	local warm_revision
	warm_revision="$(program_revision "$SNAPSHOT_DIR/warm-$name")"

	clear_output
	local clean_started_at
	local clean_elapsed
	clean_started_at="$(milliseconds)"
	compile_clean "$@"
	clean_elapsed="$(( $(milliseconds) - clean_started_at ))"
	snapshot_output "clean-$name"
	compare_snapshots "clean-$name" "warm-$name"
	run_published "clean-$name" "$expected"
	[[ "$(program_revision "$SNAPSHOT_DIR/clean-$name")" = "$warm_revision" ]] \
		|| fail "clean and warm program revisions differ for state '$name'"

	echo "REFLAXE_OCAML_SERVER_STATE:PASS state=$name clean_ms=$clean_elapsed warm_ms=$server_elapsed"
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
		HXHX_STATE_DIR="$SERVER_STATE_DIR" \
			HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
			HAXE_BIN="$HAXE_BIN" \
			bash "$SERVER_HELPER" owned-pids
	)
	printf '%s\n' "$total"
}

mkdir -p "$PROJECT_DIR" "$SNAPSHOT_DIR"
cp "$FIXTURE/build.hxml" "$PROJECT_DIR/build.hxml"
cp -R "$FIXTURE/src" "$PROJECT_DIR/src"
cp -R "$FIXTURE/shadow-primary" "$PROJECT_DIR/shadow-primary"
cp -R "$FIXTURE/shadow-fallback" "$PROJECT_DIR/shadow-fallback"
cp "$MAIN_SOURCE" "$WORK_DIR/Main.original.hx"
cp "$MESSAGE_SOURCE" "$WORK_DIR/Message.original.hx"
cp "$API_SOURCE" "$WORK_DIR/Api.original.hx"
cp "$MACRO_SOURCE" "$WORK_DIR/BuildMacro.original.hx"
cp "$BUILD_HXML" "$WORK_DIR/build.original.hxml"

expected_a=$'message=version-a\napi=1\nshadow=22\nmacro=macro-a'
expected_b=$'message=version-b\napi=1\nshadow=22\nmacro=macro-a'

clear_output
clean_a_started="$(milliseconds)"
compile_clean
clean_a_ms="$(( $(milliseconds) - clean_a_started ))"
snapshot_output clean-a
run_published clean-a "$expected_a"
revision_a="$(program_revision "$SNAPSHOT_DIR/clean-a")"

start_server

clear_output
cold_a_started="$(milliseconds)"
compile_server
cold_a_ms="$(( $(milliseconds) - cold_a_started ))"
snapshot_output cold-a
compare_snapshots clean-a cold-a
run_published cold-a "$expected_a"

warm_a_started="$(milliseconds)"
compile_server
warm_a_ms="$(( $(milliseconds) - warm_a_started ))"
snapshot_output warm-a
compare_snapshots clean-a warm-a
run_published warm-a "$expected_a"

if compile_server_with_transaction_failure >"$WORK_DIR/expected-transaction-failure.log" 2>&1; then
	fail "the injected pre-publication target failure unexpectedly succeeded"
fi
snapshot_output after-transaction-failure-a
compare_snapshots warm-a after-transaction-failure-a

replace_source_text "$MESSAGE_SOURCE" "version-a" "version-b"
compile_and_verify_state implementation-edit "$expected_b"
revision_b="$(program_revision "$SNAPSHOT_DIR/warm-implementation-edit")"
[[ "$revision_b" != "$revision_a" ]] \
	|| fail "implementation edit did not change the complete program revision"
cmp "$SNAPSHOT_DIR/warm-a/Api.ml" "$SNAPSHOT_DIR/warm-implementation-edit/Api.ml" \
	|| fail "implementation-only Message edit changed unrelated Api output"

replace_source_text "$API_SOURCE" "value():Int" "value(input:Int):Int"
replace_source_text "$API_SOURCE" "return 1;" "return input + 1;"
replace_source_text "$MAIN_SOURCE" "Api.value()" "Api.value(3)"
compile_and_verify_state public-signature-edit $'message=version-b\napi=4\nshadow=22\nmacro=macro-a'
cp "$WORK_DIR/Api.original.hx" "$API_SOURCE"
cp "$WORK_DIR/Main.original.hx" "$MAIN_SOURCE"

cp "$FIXTURE/pending/Added.hx" "$PROJECT_DIR/src/Added.hx"
replace_source_text "$MAIN_SOURCE" \
		'Sys.println("api=" + Api.value());' \
		$'Sys.println("api=" + Api.value());\n\t\tSys.println("added=" + Added.value());'
compile_and_verify_state module-added $'message=version-b\napi=1\nadded=31\nshadow=22\nmacro=macro-a'
[[ -f "$PROJECT_DIR/out/Added.ml" ]] || fail "added module has no generated target file"

cp "$WORK_DIR/Main.original.hx" "$MAIN_SOURCE"
rm "$PROJECT_DIR/src/Added.hx"
compile_and_verify_state module-deleted "$expected_b"
[[ ! -e "$PROJECT_DIR/out/Added.ml" ]] || fail "deleted module left stale target output"

cp "$FIXTURE/pending/Movable.hx" "$PROJECT_DIR/src/Movable.hx"
replace_source_text "$MAIN_SOURCE" \
		'Sys.println("api=" + Api.value());' \
		$'Sys.println("api=" + Api.value());\n\t\tSys.println("movable=" + Movable.value());'
compile_and_verify_state move-source $'message=version-b\napi=1\nmovable=41\nshadow=22\nmacro=macro-a'
mkdir "$PROJECT_DIR/moved"
mv "$PROJECT_DIR/src/Movable.hx" "$PROJECT_DIR/moved/Movable.hx"
replace_source_text "$BUILD_HXML" "-cp src" $'-cp src\n-cp moved'
compile_and_verify_state move-destination $'message=version-b\napi=1\nmovable=41\nshadow=22\nmacro=macro-a'

cp "$WORK_DIR/Main.original.hx" "$MAIN_SOURCE"
cp "$WORK_DIR/build.original.hxml" "$BUILD_HXML"
find "$PROJECT_DIR/moved" -depth -delete
compile_and_verify_state moved-module-deleted "$expected_b"
[[ ! -e "$PROJECT_DIR/out/Movable.ml" ]] || fail "removed moved module left stale target output"

rm "$PROJECT_DIR/shadow-fallback/Shadowed.hx"
compile_and_verify_state classpath-shadow-switch $'message=version-b\napi=1\nshadow=11\nmacro=macro-a'
cp "$FIXTURE/shadow-fallback/Shadowed.hx" "$PROJECT_DIR/shadow-fallback/Shadowed.hx"
compile_and_verify_state classpath-shadow-restored "$expected_b"

compile_and_verify_state define-enabled $'message=version-b\napi=1\nshadow=22\nmacro=macro-a\nfeature=7' -D feature_enabled
[[ -f "$PROJECT_DIR/out/Feature.ml" ]] || fail "define-selected module has no generated target file"
compile_and_verify_state define-disabled "$expected_b"
[[ ! -e "$PROJECT_DIR/out/Feature.ml" ]] || fail "disabled feature left stale target output"

compile_and_verify_state explicit-portable-profile "$expected_b" -D ocaml_profile=portable

replace_source_text "$BUILD_HXML" "-dce full" "-dce std"
compile_and_verify_state dce-std "$expected_b"
cp "$WORK_DIR/build.original.hxml" "$BUILD_HXML"
compile_and_verify_state dce-full-restored "$expected_b"

replace_source_text "$MACRO_SOURCE" "macro-a" "macro-b"
compile_and_verify_state build-macro-edit $'message=version-b\napi=1\nshadow=22\nmacro=macro-b'
cp "$WORK_DIR/BuildMacro.original.hx" "$MACRO_SOURCE"
compile_and_verify_state build-macro-restored "$expected_b"

prior_failure_digest="$(tree_digest "$PROJECT_DIR/out")"
replace_source_text "$MAIN_SOURCE" "Message.text()" "Message.text("
if compile_server >"$WORK_DIR/expected-server-source-failure.log" 2>&1; then
	fail "the deliberately malformed warm request unexpectedly succeeded"
fi
[[ "$(tree_digest "$PROJECT_DIR/out")" = "$prior_failure_digest" ]] \
	|| fail "malformed warm request changed the prior public output"
if compile_clean >"$WORK_DIR/expected-clean-source-failure.log" 2>&1; then
	fail "the deliberately malformed clean request unexpectedly succeeded"
fi
[[ "$(tree_digest "$PROJECT_DIR/out")" = "$prior_failure_digest" ]] \
	|| fail "malformed clean request changed the prior public output"
grep -Fq "Main.hx" "$WORK_DIR/expected-server-source-failure.log" \
	|| fail "warm failure omitted the source filename"
grep -Fq "Main.hx" "$WORK_DIR/expected-clean-source-failure.log" \
	|| fail "clean failure omitted the source filename"

cp "$WORK_DIR/Main.original.hx" "$MAIN_SOURCE"
cp "$WORK_DIR/Message.original.hx" "$MESSAGE_SOURCE"
compile_server
snapshot_output restored-a
compare_snapshots clean-a restored-a
run_published restored-a "$expected_a"
[[ "$(program_revision "$SNAPSHOT_DIR/restored-a")" = "$revision_a" ]] \
	|| fail "A-to-B-to-A did not restore the exact original program revision"

compile_server
stable_digest="$(tree_digest "$PROJECT_DIR/out")"
rss_baseline_kb="$(server_rss_kb)"
rss_peak_kb="$rss_baseline_kb"
repeated_total_ms=0
for request in 1 2 3 4 5 6 7 8 9 10; do
	started="$(milliseconds)"
	compile_server
	elapsed="$(( $(milliseconds) - started ))"
	repeated_total_ms="$((repeated_total_ms + elapsed))"
	[[ "$(tree_digest "$PROJECT_DIR/out")" = "$stable_digest" ]] \
		|| fail "unchanged repeated request $request changed generated output"
	current_rss_kb="$(server_rss_kb)"
	if (( current_rss_kb > rss_peak_kb )); then
		rss_peak_kb="$current_rss_kb"
	fi
done
rss_final_kb="$(server_rss_kb)"
if (( rss_final_kb > rss_baseline_kb + 131072 )); then
	fail "ten unchanged requests grew owned server RSS by more than 128 MiB (baseline=${rss_baseline_kb}KB final=${rss_final_kb}KB)"
fi

stop_server
start_server
clear_output
compile_server
snapshot_output restart-cold-a
compare_snapshots clean-a restart-cold-a
run_published restart-cold-a "$expected_a"

package_log="$WORK_DIR/package-server-build.log"
if ! (
	cd "$ROOT"
	REFLAXE_OCAML_SERVER_PROJECT="$PROJECT_DIR" \
		REFLAXE_OCAML_SERVER_ENDPOINT="$SERVER_PORT" \
		"$HAXE_BIN" \
		-cp packages/reflaxe.ocaml/src \
		-cp test/reflaxe_ocaml_tooling_authoring/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run ServerAuthoringFixture
) >"$package_log" 2>&1; then
	sed -n '1,240p' "$package_log" >&2
	fail "package build through the external Haxe server failed"
fi
grep -Fq "Haxe server $SERVER_PORT" "$package_log" \
	|| fail "package build did not report its external Haxe server"
grep -Fq "REFLAXE_OCAML_BUILD:PASS" "$package_log" \
	|| fail "package server build did not report success"
grep -Fq "REFLAXE_OCAML_NATIVE_TIMING:PRESENT" "$package_log" \
	|| fail "package server build did not report target/Dune timing"
grep -Fq "message=version-a" "$package_log" \
	|| fail "package server build did not run the expected native program"
grep -Fq "REFLAXE_OCAML_RUN:PASS" "$package_log" \
	|| fail "package server build did not report native execution success"
assert_no_private_state

stop_server

echo "REFLAXE_OCAML_COMPLETE_PROGRAM_SERVER:PASS clean_a_ms=$clean_a_ms cold_a_ms=$cold_a_ms warm_a_ms=$warm_a_ms repeated_10_total_ms=$repeated_total_ms rss_baseline_kb=$rss_baseline_kb rss_peak_kb=$rss_peak_kb rss_final_kb=$rss_final_kb"
