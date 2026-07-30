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
			-D reflaxe.dont_output_metadata_id
	)
}

mkdir -p "$STATE_DIR"
cp -R "$FIXTURE_TEMPLATE" "$PROJECT_DIR"

HXHX_STATE_DIR="$STATE_DIR" \
	HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
	HAXE_BIN="${HAXE_BIN:-haxe}" \
	bash "$SERVER_HELPER" start
SERVER_STARTED=1

compile_server
first_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
first_revision="$(node "$MATRIX_HELPER" source-bundle-revision "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json")"
first_executable="$(find "$PROJECT_DIR/.$OUTPUT_NAME.reflaxe-ocaml-dune-build" -type f -name "$OUTPUT_NAME.exe" -print -quit)"
first_executable_digest="$(shasum -a 256 "$first_executable" | awk '{print $1}')"
compile_server
second_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
second_executable="$(find "$PROJECT_DIR/.$OUTPUT_NAME.reflaxe-ocaml-dune-build" -type f -name "$OUTPUT_NAME.exe" -print -quit)"
second_executable_digest="$(shasum -a 256 "$second_executable" | awk '{print $1}')"

if [[ "$first_digest" != "$second_digest" ]]; then
	echo "reflaxe.ocaml exact target replay changed the complete generated tree" >&2
	exit 1
fi
if [[ "$first_executable_digest" != "$second_executable_digest" ]]; then
	echo "reflaxe.ocaml exact target replay changed the native executable digest" >&2
	exit 1
fi
if [[ -z "$second_executable" || ! -x "$second_executable" ]]; then
	echo "reflaxe.ocaml exact target replay did not preserve the native executable" >&2
	exit 1
fi
if [[ "$("$second_executable")" != "exact target replay" ]]; then
	echo "reflaxe.ocaml exact target replay changed native runtime behavior" >&2
	exit 1
fi

node "$MATRIX_HELPER" replace "$PROJECT_DIR/src/Main.hx" 'Sys.println("exact target replay");' 'Sys.println("edited exact target replay");'
compile_server
edited_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
edited_revision="$(node "$MATRIX_HELPER" source-bundle-revision "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json")"
if [[ "$edited_digest" = "$first_digest" || "$edited_revision" = "$first_revision" ]]; then
	echo "reflaxe.ocaml source edit did not invalidate exact target reuse" >&2
	exit 1
fi
compile_server
edited_hit_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
if [[ "$edited_hit_digest" != "$edited_digest" ]]; then
	echo "reflaxe.ocaml edited exact hit changed the complete generated tree" >&2
	exit 1
fi

node "$MATRIX_HELPER" replace "$PROJECT_DIR/src/Main.hx" 'Sys.println("edited exact target replay");' 'Sys.println("exact target replay");'
compile_server
restored_digest="$(node "$MATRIX_HELPER" tree-digest "$PROJECT_DIR/$OUTPUT_NAME")"
restored_revision="$(node "$MATRIX_HELPER" source-bundle-revision "$PROJECT_DIR/$OUTPUT_NAME/ocaml_artifact_manifest.json")"
if [[ "$restored_digest" != "$first_digest" || "$restored_revision" != "$first_revision" ]]; then
	echo "reflaxe.ocaml A-to-B-to-A replay did not restore the original source result" >&2
	exit 1
fi

echo "REFLAXE_OCAML_TARGET_REUSE_EXACT_HIT:PASS digest=$restored_digest"
