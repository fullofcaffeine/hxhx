#!/usr/bin/env bash
set -euo pipefail

# Proves that the real standalone OCaml target admits one successful miss and
# then skips its complete miss-only preparation on an exact server request.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$ROOT/test/reflaxe_ocaml_target_reuse_exact"
SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
MATRIX_HELPER="$ROOT/scripts/ci/reflaxe-ocaml-server-matrix-helper.js"
STATE_DIR="$(mktemp -d "$ROOT/.reflaxe-ocaml-target-reuse-exact-state.XXXXXX")"
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
	if [[ -d "$FIXTURE/$OUTPUT_NAME" ]]; then
		find "$FIXTURE/$OUTPUT_NAME" -depth -delete
	fi
	if [[ -d "$FIXTURE/.$OUTPUT_NAME.reflaxe-ocaml-dune-build" ]]; then
		find "$FIXTURE/.$OUTPUT_NAME.reflaxe-ocaml-dune-build" -depth -delete
	fi
	if [[ -d "$STATE_DIR" ]]; then
		find "$STATE_DIR" -depth -delete
	fi
}
trap cleanup EXIT

compile_server() {
	(
		cd "$FIXTURE"
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

HXHX_STATE_DIR="$STATE_DIR" \
	HXHX_HAXE_SERVER_PORT="$SERVER_PORT" \
	HAXE_BIN="${HAXE_BIN:-haxe}" \
	bash "$SERVER_HELPER" start
SERVER_STARTED=1

compile_server
first_digest="$(node "$MATRIX_HELPER" tree-digest "$FIXTURE/$OUTPUT_NAME")"
first_executable="$(find "$FIXTURE/.$OUTPUT_NAME.reflaxe-ocaml-dune-build" -type f -name "$OUTPUT_NAME.exe" -print -quit)"
first_executable_digest="$(shasum -a 256 "$first_executable" | awk '{print $1}')"
compile_server
second_digest="$(node "$MATRIX_HELPER" tree-digest "$FIXTURE/$OUTPUT_NAME")"
second_executable="$(find "$FIXTURE/.$OUTPUT_NAME.reflaxe-ocaml-dune-build" -type f -name "$OUTPUT_NAME.exe" -print -quit)"
second_executable_digest="$(shasum -a 256 "$second_executable" | awk '{print $1}')"

if [[ "$first_digest" != "$second_digest" ]]; then
	echo "reflaxe.ocaml exact target replay changed the complete generated tree" >&2
	exit 1
fi
if [[ "$first_executable_digest" != "$second_executable_digest" ]]; then
	echo "reflaxe.ocaml exact target replay changed the native executable digest" >&2
	exit 1
fi
node "$MATRIX_HELPER" source-bundle-revision "$FIXTURE/$OUTPUT_NAME/ocaml_artifact_manifest.json" >/dev/null
if [[ -z "$second_executable" || ! -x "$second_executable" ]]; then
	echo "reflaxe.ocaml exact target replay did not preserve the native executable" >&2
	exit 1
fi
if [[ "$("$second_executable")" != "exact target replay" ]]; then
	echo "reflaxe.ocaml exact target replay changed native runtime behavior" >&2
	exit 1
fi
echo "REFLAXE_OCAML_TARGET_REUSE_EXACT_HIT:PASS digest=$second_digest"
