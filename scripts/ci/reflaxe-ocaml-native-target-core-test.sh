#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_SOURCE="$ROOT/test/reflaxe_ocaml_native_program_host/src"
HAXE_BIN="${HAXE_BIN:-$ROOT/node_modules/.bin/haxe}"
mkdir -p "$ROOT/.tmp"
WORK_ROOT="$(mktemp -d "$ROOT/.tmp/reflaxe-ocaml-native-target-core.XXXXXX")"
HOST_OUTPUT="$WORK_ROOT/host"
REFERENCE_OUTPUT="$WORK_ROOT/reference-app"
APP_OUTPUT="$WORK_ROOT/app"

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

for command_name in dune node "$HAXE_BIN"; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "Missing required native target-core command: $command_name" >&2
		exit 2
	fi
done

cd "$ROOT"
run_background "$HAXE_BIN" \
	-cp packages/reflaxe.ocaml/src \
	-cp "$FIXTURE_SOURCE" \
	--run NativeTargetCoreRuntimeFixture \
	"$REFERENCE_OUTPUT"

reference_program_output="$("$REFERENCE_OUTPUT/_build/default/reflaxe_ocaml_entry.exe")"
if [[ -n "$reference_program_output" ]]; then
	echo "Interpreted target-core reference app produced unexpected runtime output." >&2
	printf '%s\n' "$reference_program_output" >&2
	exit 1
fi

run_background "$HAXE_BIN" \
	-cp packages/reflaxe.ocaml/src \
	-cp "$FIXTURE_SOURCE" \
	--main NativeTargetCoreRuntimeFixture \
	--no-output \
	-lib reflaxe.ocaml \
	-D "ocaml_output=$HOST_OUTPUT" \
	-D ocaml_no_build \
	-D no-traces \
	-D no_traces

if grep -Eq '^let (create|__empty) =' "$HOST_OUTPUT/reflaxe_ocaml_target_OcamlTargetDeclarationCodec.ml"; then
	echo "Abstract target declaration helpers unexpectedly expose a constructible OCaml class." >&2
	exit 1
fi

run_background dune build --root "$HOST_OUTPUT" ./host.exe
run_background "$HOST_OUTPUT/_build/default/host.exe" "$APP_OUTPUT"

program_output="$($APP_OUTPUT/_build/default/reflaxe_ocaml_entry.exe)"
if [[ -n "$program_output" ]]; then
	echo "Native target-core app produced unexpected runtime output." >&2
	printf '%s\n' "$program_output" >&2
	exit 1
fi

node - "$REFERENCE_OUTPUT" "$APP_OUTPUT" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const assert = require('assert/strict')

const referenceOutput = process.argv[2]
const nativeOutput = process.argv[3]
const readJson = (output, name) => JSON.parse(fs.readFileSync(path.join(output, name), 'utf8'))
const referenceReport = readJson(referenceOutput, 'ocaml_shared_target_report.json')
const referenceManifest = readJson(referenceOutput, 'ocaml_shared_target_manifest.json')
const report = readJson(nativeOutput, 'ocaml_shared_target_report.json')
const manifest = readJson(nativeOutput, 'ocaml_shared_target_manifest.json')

if (report.schemaVersion !== 1 || report.route !== 'native-target-core-runtime') {
	throw new Error('native target-core report has the wrong schema or route')
}
if (report.targetCoreId !== 'reflaxe.ocaml.target-program-core.v1') {
	throw new Error('native target-core report has the wrong standalone core identity')
}
for (const key of ['normalizedInputIdentity', 'loweredPlanIdentity', 'runtimeReasonIdentity', 'outputManifestIdentity']) {
	if (typeof report[key] !== 'string' || !/^[a-f0-9]{64}$/.test(report[key])) {
		throw new Error(`native target-core report has an invalid ${key}`)
	}
}
if (manifest.outputManifestIdentity !== report.outputManifestIdentity) {
	throw new Error('native target-core report and manifest identities differ')
}
if (!Array.isArray(report.runtimeReasons) || report.runtimeReasons.length !== 0) {
	throw new Error('runtime-free native target-core tracer recorded runtime requirements')
}
for (const file of report.files) {
	const contents = fs.readFileSync(path.join(nativeOutput, file.path))
	const digest = crypto.createHash('sha256').update(contents).digest('hex')
	if (digest !== file.sha256) {
		throw new Error(`native target-core file hash differs for ${file.path}`)
	}
	const referenceContents = fs.readFileSync(path.join(referenceOutput, file.path))
	if (!contents.equals(referenceContents)) {
		throw new Error(`native and interpreted target-core files differ for ${file.path}`)
	}
}
assert.deepStrictEqual(report, referenceReport, 'native and interpreted target-core reports differ')
assert.deepStrictEqual(manifest, referenceManifest, 'native and interpreted target-core manifests differ')
NODE

if ! grep -Fxq 'and value = let inner = 7 in inner' "$APP_OUTPUT/Main.ml"; then
	echo "Native target-core fixture produced an unexpected Main.value initializer." >&2
	exit 1
fi

if ! grep -Fxq 'let main = fun () -> ignore ()' "$APP_OUTPUT/Main.ml"; then
	echo "Native target-core fixture produced an unexpected Main.main function." >&2
	exit 1
fi

echo "REFLAXE_OCAML_NATIVE_TARGET_CORE:PASS"
