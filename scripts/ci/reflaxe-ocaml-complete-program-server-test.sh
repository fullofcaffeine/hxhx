#!/usr/bin/env bash
set -euo pipefail

# Proves the practical warm-server contract through the real standalone OCaml
# target. Haxe may reuse unchanged frontend modules, but every Reflaxe request
# must still receive one complete current program and publish one complete
# generated tree.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$ROOT/test/portable/fixtures/call_exact_int_static"
SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
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
SOURCE_FILE="$PROJECT_DIR/src/Arithmetic.hx"
ORIGINAL_SOURCE="$WORK_DIR/Arithmetic.original.hx"
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

replace_source_text() {
	local expected="$1"
	local replacement="$2"
	node - "$SOURCE_FILE" "$expected" "$replacement" <<'NODE'
const fs = require('fs')
const [sourcePath, expected, replacement] = process.argv.slice(2)
const source = fs.readFileSync(sourcePath, 'utf8')
const occurrences = source.split(expected).length - 1
if (occurrences !== 1) {
	throw new Error(`expected exactly one source occurrence of ${JSON.stringify(expected)}, found ${occurrences}`)
}
fs.writeFileSync(sourcePath, source.replace(expected, replacement))
NODE
}

clear_output() {
	if [[ -d "$PROJECT_DIR/out" ]]; then
		find "$PROJECT_DIR/out" -depth -delete
	fi
}

compile_clean() {
	(
		cd "$PROJECT_DIR"
		"$HAXE_BIN" build.hxml \
			-D ocaml_no_build \
			-D reflaxe_output_transaction \
			-D reflaxe.dont_output_metadata_id
	)
}

compile_server() {
	(
		cd "$PROJECT_DIR"
		"$HAXE_BIN" --connect "$SERVER_PORT" build.hxml \
			-D ocaml_no_build \
			-D reflaxe_output_transaction \
			-D reflaxe.dont_output_metadata_id
	)
}

compile_server_with_transaction_failure() {
	(
		cd "$PROJECT_DIR"
		"$HAXE_BIN" --connect "$SERVER_PORT" build.hxml \
			-D ocaml_no_build \
			-D reflaxe_output_transaction \
			-D reflaxe.dont_output_metadata_id \
			-D reflaxe_output_transaction_test_fail_before_commit
	)
}

snapshot_output() {
	local name="$1"
	local destination="$SNAPSHOT_DIR/$name"
	[[ -f "$PROJECT_DIR/out/ocaml_artifact_manifest.json" ]] \
		|| fail "request '$name' did not publish the artifact manifest"
	[[ -f "$PROJECT_DIR/out/_GeneratedFiles.json" ]] \
		|| fail "request '$name' did not publish the complete generated-file receipt"
	mkdir -p "$destination"
	cp -R "$PROJECT_DIR/out/." "$destination/"
	if find "$PROJECT_DIR" -maxdepth 1 -type d -name '.*.reflaxe-output-transaction' -print -quit | grep -q .; then
		fail "request '$name' left private output transaction state"
	fi
	if grep -R -F '.reflaxe-output-transaction' "$PROJECT_DIR/out" >/dev/null; then
		fail "request '$name' leaked a private transaction path into generated output"
	fi
}

compare_snapshots() {
	local expected="$1"
	local actual="$2"
	diff -ru "$SNAPSHOT_DIR/$expected" "$SNAPSHOT_DIR/$actual" \
		|| fail "generated target trees differ: expected '$expected', got '$actual'"
}

program_revision() {
	local name="$1"
	node - "$SNAPSHOT_DIR/$name/ocaml_artifact_manifest.json" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (typeof report.programRevision !== 'string' || report.programRevision.length === 0) {
	throw new Error('artifact manifest is missing programRevision')
}
process.stdout.write(report.programRevision)
NODE
}

mkdir -p "$PROJECT_DIR" "$SNAPSHOT_DIR"
cp "$FIXTURE/build.hxml" "$PROJECT_DIR/build.hxml"
cp -R "$FIXTURE/src" "$PROJECT_DIR/src"
cp "$SOURCE_FILE" "$ORIGINAL_SOURCE"

clear_output
compile_clean
snapshot_output clean_a
revision_a="$(program_revision clean_a)"

if "$HAXE_BIN" --connect "$SERVER_PORT" --version >/dev/null 2>&1; then
	fail "chosen compiler-server port $SERVER_PORT is already in use"
fi
HXHX_STATE_DIR="$SERVER_STATE_DIR" \
	HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
	HAXE_BIN="$HAXE_BIN" \
	bash "$SERVER_HELPER" start
SERVER_STARTED=1

clear_output
compile_server
snapshot_output cold_a
compare_snapshots clean_a cold_a

compile_server
snapshot_output warm_a
compare_snapshots clean_a warm_a

if compile_server_with_transaction_failure >"$WORK_DIR/expected-transaction-failure.log" 2>&1; then
	fail "the injected pre-publication target failure unexpectedly succeeded"
fi
snapshot_output after_transaction_failure_a
compare_snapshots warm_a after_transaction_failure_a

replace_source_text "return value + 1;" "return value + 2;"
compile_server
snapshot_output warm_b
revision_b="$(program_revision warm_b)"
[[ "$revision_b" != "$revision_a" ]] \
	|| fail "one function-body edit did not change the complete program revision"
cmp "$SNAPSHOT_DIR/warm_a/BoolCalls.ml" "$SNAPSHOT_DIR/warm_b/BoolCalls.ml" \
	|| fail "the Arithmetic body edit changed unrelated BoolCalls output"

clear_output
compile_clean
snapshot_output clean_b
compare_snapshots clean_b warm_b

replace_source_text "return value + 2;" "return value + ;"
if compile_server >"$WORK_DIR/expected-failure.log" 2>&1; then
	fail "the deliberately malformed warm request unexpectedly succeeded"
fi
snapshot_output after_failed_b
compare_snapshots warm_b after_failed_b

cp "$ORIGINAL_SOURCE" "$SOURCE_FILE"
compile_server
snapshot_output restored_a
compare_snapshots clean_a restored_a
[[ "$(program_revision restored_a)" = "$revision_a" ]] \
	|| fail "A -> B -> failed request -> A did not restore the exact original program revision"

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

echo "REFLAXE_OCAML_COMPLETE_PROGRAM_SERVER:PASS"
