#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$ROOT/test/reflaxe_ocaml_shared_expression"
HAXE_BIN="${HAXE_BIN:-$ROOT/node_modules/.bin/haxe}"
mkdir -p "$ROOT/.tmp"
WORK_ROOT="$(mktemp -d "$ROOT/.tmp/reflaxe-ocaml-shared-expression.XXXXXX")"
OUTPUT_DIR="$WORK_ROOT/out"

cleanup() {
	find "$WORK_ROOT" -depth -delete
}
trap cleanup EXIT

run_background() {
	if command -v taskpolicy >/dev/null 2>&1 && command -v nice >/dev/null 2>&1; then
		taskpolicy -b nice -n 10 "$@"
	elif command -v nice >/dev/null 2>&1; then
		nice -n 10 "$@"
	else
		"$@"
	fi
}

for command_name in dune "$HAXE_BIN"; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "Missing required shared-expression command: $command_name" >&2
		exit 2
	fi
done

(
	cd "$FIXTURE"
	run_background "$HAXE_BIN" build.hxml \
		-D "ocaml_output=$OUTPUT_DIR" \
		-D 'reflaxe_ocaml_target_expression_test_require_shared=field-initializer:static:Main|Main::value' \
		-D 'reflaxe_ocaml_target_function_test_require_shared=Main|Main::main'
)

if ! grep -Fxq 'let value = let inner = 7 in inner' "$OUTPUT_DIR/Main.ml"; then
	echo "Shared-expression fixture produced an unexpected Main.value initializer." >&2
	exit 1
fi

if ! grep -Fxq 'let main = fun () -> ignore ()' "$OUTPUT_DIR/Main.ml"; then
	echo "Shared-expression fixture produced an unexpected Main.main function." >&2
	exit 1
fi

node - "$OUTPUT_DIR/ocaml_shared_target_report.json" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (report.schemaVersion !== 1 || report.route !== 'stock-haxe') {
	throw new Error('shared target report did not record the stock Haxe route')
}
if (report.targetCoreId !== 'reflaxe.ocaml.target-program-core.v1') {
	throw new Error('shared target report did not execute the standalone target core')
}
for (const key of ['normalizedInputIdentity', 'loweredPlanIdentity', 'runtimeReasonIdentity', 'outputManifestIdentity']) {
	if (typeof report[key] !== 'string' || !/^[a-f0-9]{64}$/.test(report[key])) {
		throw new Error(`shared target report has an invalid ${key}`)
	}
}
if (!Array.isArray(report.runtimeReasons) || report.runtimeReasons.length !== 0) {
	throw new Error('runtime-free shared target tracer recorded unexpected runtime requirements')
}
NODE

(
	cd "$OUTPUT_DIR"
	run_background dune build ./out.exe
)

program_output="$($OUTPUT_DIR/_build/default/out.exe)"
if [[ -n "$program_output" ]]; then
	echo "Shared-expression fixture produced unexpected runtime output." >&2
	printf '%s\n' "$program_output" >&2
	exit 1
fi

echo "REFLAXE_OCAML_SHARED_EXPRESSION:PASS"
