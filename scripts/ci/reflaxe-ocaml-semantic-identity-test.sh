#!/usr/bin/env bash
set -euo pipefail

# Proves that process-local Haxe variable numbers cannot change standalone
# reflaxe.ocaml artifacts. Both target compilations use the same source,
# defines, output path, and target configuration. The second compilation only
# allocates unrelated macro locals before the user program is typed.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$ROOT/test/portable/fixtures/call_exact_int_static"
PROBE_SOURCE="$ROOT/test/reflaxe_ocaml_semantic_identity/src"
HAXE_BIN="${HAXE_BIN:-haxe}"
HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "reflaxe.ocaml semantic-identity test: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
	exit 1
fi
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-ocaml-semantic-identity.XXXXXX")"
OUTPUT_NAME="out_semantic_identity_$$"
OUTPUT_DIR="$FIXTURE/$OUTPUT_NAME"
OUTPUT_EXE="$FIXTURE/${OUTPUT_NAME}.exe"

cleanup() {
	if [[ -d "$OUTPUT_DIR" ]]; then
		find "$OUTPUT_DIR" -depth -delete
	fi
	if [[ -f "$OUTPUT_EXE" ]]; then
		find "$OUTPUT_EXE" -delete
	fi
	if [[ -d "$WORK_DIR" ]]; then
		find "$WORK_DIR" -depth -delete
	fi
}
trap cleanup EXIT

sha256_tree() {
	local output_dir="$1"
	(
		cd "$FIXTURE"
		find "$output_dir" -type f ! -path '*/_build/*' -print0 \
			| sort -z \
			| xargs -0 shasum -a 256 \
			| sed "s#  ${output_dir}/#  TREE/#"
	)
}

compile_probe() {
	local perturb="$1"
	local raw_probe="$2"
	(
		cd "$FIXTURE"
		REFLAXE_OCAML_IDENTITY_PERTURB="$perturb" \
		REFLAXE_OCAML_IDENTITY_PROBE_PATH="$raw_probe" \
			"$HAXE_BIN" build.hxml \
			-cp "$PROBE_SOURCE" \
			--macro "ReflaxeOcamlSemanticIdentityProbe.run()" \
			-D ocaml_no_build \
			-D "ocaml_output=$OUTPUT_NAME"
	)
}

compile_probe 0 "$WORK_DIR/baseline.raw"
cp "$OUTPUT_DIR/ocaml_lowering_report.json" "$WORK_DIR/baseline.lowering.json"
sha256_tree "$OUTPUT_NAME" >"$WORK_DIR/baseline.tree.sha256"
find "$OUTPUT_DIR" -depth -delete
if [[ -f "$OUTPUT_EXE" ]]; then
	find "$OUTPUT_EXE" -delete
fi

compile_probe 1 "$WORK_DIR/perturbed.raw"

if cmp -s "$WORK_DIR/baseline.raw" "$WORK_DIR/perturbed.raw"; then
	echo "The regression setup did not shift Haxe's process-local variable numbers." >&2
	exit 1
fi

cmp "$WORK_DIR/baseline.lowering.json" "$OUTPUT_DIR/ocaml_lowering_report.json"
sha256_tree "$OUTPUT_NAME" >"$WORK_DIR/perturbed.tree.sha256"
cmp "$WORK_DIR/baseline.tree.sha256" "$WORK_DIR/perturbed.tree.sha256"

echo "REFLAXE_OCAML_SEMANTIC_IDENTITY:PASS"
