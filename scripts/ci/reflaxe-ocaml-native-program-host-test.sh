#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_FIXTURE="$ROOT/test/reflaxe_ocaml_shared_expression"
HOST_FIXTURE_SOURCE="$ROOT/test/reflaxe_ocaml_native_program_host/src"
HAXE_BIN="${HAXE_BIN:-$ROOT/node_modules/.bin/haxe}"
mkdir -p "$ROOT/.tmp"
PRESERVED_WORK_ROOT="${REFLAXE_OCAML_NATIVE_PROGRAM_HOST_WORK_ROOT:-}"
if [[ -n "$PRESERVED_WORK_ROOT" ]]; then
	if [[ ! -d "$PRESERVED_WORK_ROOT" ]]; then
		echo "Native program-host preserved work root does not exist: $PRESERVED_WORK_ROOT" >&2
		exit 2
	fi
	WORK_ROOT="$(cd "$PRESERVED_WORK_ROOT" && pwd -P)"
	REUSED_GENERATION=1
else
	WORK_ROOT="$(mktemp -d "$ROOT/.tmp/reflaxe-ocaml-native-program-host.XXXXXX")"
	REUSED_GENERATION=0
fi
STOCK_COMPILER_OUTPUT="$WORK_ROOT/stock-compiler/out"
STOCK_SHARED_OUTPUT="$WORK_ROOT/stock-shared-output"
NATIVE_HOST_OUTPUT="$WORK_ROOT/native-host"
NATIVE_SHARED_OUTPUT="$WORK_ROOT/native-shared-output"
STOCK_DIAGNOSTICS="$WORK_ROOT/stock-haxe.stderr.log"
NATIVE_DIAGNOSTICS="$WORK_ROOT/native-hxhx.stderr.log"

cleanup() {
	local status="$?"
	if [[ "$REUSED_GENERATION" -eq 1 ]]; then
		echo "native_program_host_preserved_artifacts=$WORK_ROOT" >&2
		return "$status"
	fi
	if [[ "$status" -ne 0 ]]; then
		echo "native_program_host_failure_artifacts=$WORK_ROOT" >&2
		return "$status"
	fi
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

for command_name in dune node "$HAXE_BIN"; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "Missing required native program-host command: $command_name" >&2
		exit 2
	fi
done

cd "$ROOT"
if [[ "$REUSED_GENERATION" -eq 0 ]]; then
	(
		cd "$APP_FIXTURE"
		run_background "$HAXE_BIN" build.hxml \
			-D "ocaml_output=$STOCK_COMPILER_OUTPUT" \
			-D "reflaxe_ocaml_shared_program_output=$STOCK_SHARED_OUTPUT" \
			-D 'reflaxe_ocaml_target_expression_test_require_shared=field-initializer:static:Main|Main::value' \
			-D 'reflaxe_ocaml_target_function_test_require_shared=Main|Main::main'
	) 2> >(tee "$STOCK_DIAGNOSTICS" >&2)

	run_background dune build --root "$STOCK_COMPILER_OUTPUT" ./out.exe
	stock_compiler_program_output="$("$STOCK_COMPILER_OUTPUT/_build/default/out.exe")"
	if [[ -n "$stock_compiler_program_output" ]]; then
		echo "Stock Haxe compiler output produced unexpected runtime output." >&2
		printf '%s\n' "$stock_compiler_program_output" >&2
		exit 1
	fi

	run_background dune build --root "$STOCK_SHARED_OUTPUT" ./reflaxe_ocaml_entry.exe
	stock_shared_program_output="$("$STOCK_SHARED_OUTPUT/_build/default/reflaxe_ocaml_entry.exe")"
	if [[ -n "$stock_shared_program_output" ]]; then
		echo "Stock Haxe shared-target output produced unexpected runtime output." >&2
		printf '%s\n' "$stock_shared_program_output" >&2
		exit 1
	fi

	host_compile_started="$(date +%s)"
	run_background "$HAXE_BIN" \
		-cp packages/hxhx-core/src \
		-cp packages/reflaxe.ocaml/src \
		-cp "$HOST_FIXTURE_SOURCE" \
		--main NativeProgramHostFixture \
		--no-output \
		-lib reflaxe.ocaml \
		-D "ocaml_output=$NATIVE_HOST_OUTPUT" \
		-D ocaml_no_build \
		-D no-traces \
		-D no_traces
	host_compile_finished="$(date +%s)"
	host_compile_seconds="$((host_compile_finished - host_compile_started))"
else
	for required_path in \
		"$STOCK_COMPILER_OUTPUT/_build/default/out.exe" \
		"$STOCK_SHARED_OUTPUT/_build/default/reflaxe_ocaml_entry.exe" \
		"$NATIVE_HOST_OUTPUT/_GeneratedFiles.json"; do
		if [[ ! -f "$required_path" ]]; then
			echo "Preserved native program-host work is incomplete: $required_path" >&2
			exit 2
		fi
	done
	host_compile_seconds="reused-preserved-generation"
fi

node - "$NATIVE_HOST_OUTPUT/_GeneratedFiles.json" <<'NODE'
const fs = require('fs')
const receipt = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const forbidden = receipt.filesGenerated.filter((file) => /(^|_)(EmitterStage|OcamlStage3)|ocaml_stage3/i.test(file))
if (forbidden.length !== 0) {
	throw new Error(`native program host retained Stage3 modules: ${forbidden.join(', ')}`)
}
NODE

native_host_name="$(awk '/^[[:space:]]*\(name[[:space:]]+/ { line=$0; sub(/^[[:space:]]*\(name[[:space:]]+/, "", line); sub(/\).*/, "", line); print line; exit }' "$NATIVE_HOST_OUTPUT/dune")"
if [[ ! "$native_host_name" =~ ^[A-Za-z0-9_]+$ ]]; then
	echo "Could not resolve the generated native program-host executable name." >&2
	exit 1
fi
run_background dune build --root "$NATIVE_HOST_OUTPUT" "./$native_host_name.exe"
native_host_executable="$NATIVE_HOST_OUTPUT/_build/default/$native_host_name.exe"
native_host_output="$("$native_host_executable" "$APP_FIXTURE/src" "$NATIVE_SHARED_OUTPUT" 2> >(tee "$NATIVE_DIAGNOSTICS" >&2))"
if ! grep -Fxq 'native_hxhx_diagnostics=0' <<<"$native_host_output"; then
	echo "Native hxhx did not report a clean diagnostic set." >&2
	printf '%s\n' "$native_host_output" >&2
	exit 1
fi
if ! grep -Fxq 'native_hxhx_source_modules=Main' <<<"$native_host_output"; then
	echo "Native hxhx resolved an unexpected source dependency set." >&2
	printf '%s\n' "$native_host_output" >&2
	exit 1
fi

native_shared_program_output="$("$NATIVE_SHARED_OUTPUT/_build/default/reflaxe_ocaml_entry.exe")"
if [[ -n "$native_shared_program_output" ]]; then
	echo "Native hxhx shared-target output produced unexpected runtime output." >&2
	printf '%s\n' "$native_shared_program_output" >&2
	exit 1
fi

if grep -Eiq '(^|[[:space:]])(warning|error)(:|[[:space:]])' "$STOCK_DIAGNOSTICS" "$NATIVE_DIAGNOSTICS"; then
	echo "Stock Haxe or native hxhx reported a warning or error for the accepted program." >&2
	exit 1
fi

node - "$STOCK_SHARED_OUTPUT" "$NATIVE_SHARED_OUTPUT" <<'NODE'
const assert = require('assert/strict')
const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const stockOutput = process.argv[2]
const nativeOutput = process.argv[3]
const readJson = (output, name) => JSON.parse(fs.readFileSync(path.join(output, name), 'utf8'))
const stockReport = readJson(stockOutput, 'ocaml_shared_target_report.json')
const nativeReport = readJson(nativeOutput, 'ocaml_shared_target_report.json')
const stockManifest = readJson(stockOutput, 'ocaml_shared_target_manifest.json')
const nativeManifest = readJson(nativeOutput, 'ocaml_shared_target_manifest.json')
const comparableReportKeys = [
	'schemaVersion',
	'targetCoreId',
	'normalizedInputIdentity',
	'normalizedClassIdentity',
	'normalizedClassIdentityFacts',
	'normalizedFieldIdentities',
	'normalizedFunctionIdentities',
	'loweredPlanIdentity',
	'runtimeReasonIdentity',
	'outputManifestIdentity',
	'mainModuleId',
	'dependencyModuleIds',
	'runtimeReasons',
	'files'
]
const select = (value) => Object.fromEntries(comparableReportKeys.map((key) => [key, value[key]]))

if (stockReport.route !== 'stock-haxe' || nativeReport.route !== 'native-hxhx') {
	throw new Error('dual-host reports did not identify their compiler routes')
}
assert.deepStrictEqual(select(nativeReport), select(stockReport), 'stock Haxe and native hxhx target plans differ')
assert.deepStrictEqual(nativeManifest, stockManifest, 'stock Haxe and native hxhx manifests differ')
if (nativeReport.dependencyModuleIds.length !== 0 || nativeReport.runtimeReasons.length !== 0) {
	throw new Error('revision 1 program unexpectedly retained source or runtime dependencies')
}
for (const file of nativeReport.files) {
	const stockContents = fs.readFileSync(path.join(stockOutput, file.path))
	const nativeContents = fs.readFileSync(path.join(nativeOutput, file.path))
	const digest = crypto.createHash('sha256').update(nativeContents).digest('hex')
	if (digest !== file.sha256) {
		throw new Error(`native hxhx target file hash differs for ${file.path}`)
	}
	if (!nativeContents.equals(stockContents)) {
		throw new Error(`stock Haxe and native hxhx target files differ for ${file.path}`)
	}
}
NODE

if ! grep -Fxq 'and value = let inner = 7 in inner' "$NATIVE_SHARED_OUTPUT/Main.ml"; then
	echo "Native hxhx produced an unexpected Main.value initializer." >&2
	exit 1
fi
if ! grep -Fxq 'let main = fun () -> ignore ()' "$NATIVE_SHARED_OUTPUT/Main.ml"; then
	echo "Native hxhx produced an unexpected Main.main function." >&2
	exit 1
fi

echo "native_program_host_compile_seconds=$host_compile_seconds"
echo "REFLAXE_OCAML_NATIVE_PROGRAM_HOST:PASS"
