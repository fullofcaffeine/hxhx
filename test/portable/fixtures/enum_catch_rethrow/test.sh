#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
RUNTIME_REPORT_FILE="out/ocaml_runtime_requirement_report.json"
INSPECTION_REPORT="$(mktemp)"
INVALID_LOG="$(mktemp)"
INVALID_OUTPUT="out-invalid-enum-rethrow-$$"
NEGATIVE_OUTPUT="out-negative-enum-rethrow-$$"
trap 'rm -f "$INSPECTION_REPORT" "$INVALID_LOG"; rm -rf "$INVALID_OUTPUT" "$NEGATIVE_OUTPUT"' EXIT

node - "$SOURCE_FILE" "$REPORT_FILE" "$RUNTIME_REPORT_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const runtime = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'))

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 87
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v27'
	|| report.controlCatchModel !== 'typed-ocaml-represented-value-catch-chain-v7') {
	fail('unexpected enum catch-rethrow report contract')
}

const controls = report.controls.filter(item =>
	item.proofId === 'exact-enum-catch-binding-rethrow-control-v1')
if (controls.length !== 6) {
	fail(`expected six enum catch-binding rethrows, got ${controls.length}`)
}
if (new Set(controls.map(item => item.payload.enumCatchOrigin.localId)).size !== controls.length) {
	fail('same-named enum catches did not retain distinct lexical origins')
}
for (const control of controls) {
	const payload = control.payload
	const origin = payload?.enumCatchOrigin
	const chain = report.controlCatches.find(item => item.id === origin?.chainId)
	const clause = chain?.clauses.find(item => item.id === origin?.clauseId)
	if (control.pipelineRevision !== 'ocaml-function-plans-v114'
		|| payload?.conversion !== 'preserve-enum-catch-throw-carrier'
		|| payload.proofId !== control.proofId
		|| payload.inputRepresentationId !== `control-representation:enum-catch-v1:${payload.inputSemanticTypeId}`
		|| payload.outputRepresentationId !== payload.inputRepresentationId
		|| payload.inputCarrierTypeId !== `haxe-enum-native-variant-carrier-v1:${payload.inputSemanticTypeId}`
		|| payload.outputCarrierTypeId !== payload.inputCarrierTypeId
		|| control.runtimeTags.join(',') !== `Dynamic,${payload.inputSemanticTypeId}`
		|| origin?.localId !== clause?.localId
		|| origin.semanticTypeId !== clause.semanticTypeId
		|| origin.carrierTypeId !== clause.outputCarrierTypeId
		|| origin.representationId !== clause.outputRepresentationId
		|| origin.functionId !== control.functionId
		|| origin.programRevision !== control.programRevision
		|| origin.bodyRevision !== control.bodyRevision
		|| origin.pipelineRevision !== control.pipelineRevision) {
		fail(`rethrow ${control.id} lost its exact catch origin`)
	}
	const requirement = runtime.requirements.find(item =>
		item.id === `${origin.clauseId}:runtime:haxe-enum-catch-payload-recovery-v1`)
	if (requirement?.subject?.id !== payload.inputSemanticTypeId
		|| requirement.rootModules.join(',') !== 'HxEnum') {
		fail(`rethrow ${control.id} lost its HxEnum runtime requirement`)
	}
	if (runtime.requirements.some(item =>
		item.id === `${control.id}:runtime:haxe-enum-dynamic-box`)) {
		fail(`rethrow ${control.id} incorrectly owns a fresh enum-boxing requirement`)
	}
}

const preservedRethrows = source.match(/HxType\.hx_throw_typed_rtti __enum_catch_carrier_[0-9]+/g) ?? []
const freshRethrowBoxes = source.match(/HxEnum\.box_if_needed "(?:Signal|haxe\.io\.Error)" \(Obj\.repr error\)/g) ?? []
if (preservedRethrows.length !== 12 || freshRethrowBoxes.length !== 0) {
	fail('generated OCaml did not preserve all six original catch carriers on both input channels')
}
if (runtime.authorityStatus !== 'partial'
	|| !runtime.requirementRootModules.includes('HxEnum')) {
	fail('runtime report lost the enum rethrow dependency')
}
NODE

"$HAXE_BIN" -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$INSPECTION_REPORT"

node - "$INSPECTION_REPORT" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const controls = report.lowering.controls.filter(item =>
	item.proofId === 'exact-enum-catch-binding-rethrow-control-v1')
if (report.schemaVersion !== 48
	|| report.summary.valid !== true
	|| controls.length !== 6
	|| controls.some(item => item.payload?.enumCatchOrigin?.localId == null)) {
	throw new Error('public inspection lost the enum catch-binding rethrow proof')
}
NODE

cp -R out "$INVALID_OUTPUT"
node - "$INVALID_OUTPUT/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const control = report.controls.find(item =>
	item.proofId === 'exact-enum-catch-binding-rethrow-control-v1')
if (control?.payload?.enumCatchOrigin == null)
	throw new Error('missing enum catch origin to corrupt')
const foreign = report.controlCatches
	.flatMap(chain => chain.clauses.map(clause => ({chain, clause})))
	.find(item => item.clause.id !== control.payload.enumCatchOrigin.clauseId)
if (foreign == null)
	throw new Error('missing foreign catch clause')
control.payload.enumCatchOrigin.chainId = foreign.chain.id
control.payload.enumCatchOrigin.clauseId = foreign.clause.id
control.payload.enumCatchOrigin.localId = foreign.clause.localId
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE

"$HAXE_BIN" -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision \
	"$INVALID_OUTPUT/ocaml_lowering_report.json"
if "$HAXE_BIN" -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output "$INVALID_OUTPUT" --require-lowering --json \
	>"$INVALID_LOG" 2>&1; then
	echo "The inspector accepted a foreign enum catch origin" >&2
	exit 1
fi
if ! grep -Fq "does not refer to its exact enum catch clause" "$INVALID_LOG"; then
	echo "The inspector rejected the foreign enum catch origin for an unexpected reason" >&2
	cat "$INVALID_LOG" >&2
	exit 1
fi

for define in enum_rethrow_mutation enum_rethrow_capture enum_rethrow_alias enum_rethrow_cast; do
	rm -rf "$NEGATIVE_OUTPUT"
	if "$HAXE_BIN" -cp "$ROOT/test/oracle/reflaxe_ocaml_enum_rethrow_negative_seed/src" \
		-main Main --no-output -lib reflaxe.ocaml -D ocaml_emit_only \
		-D "ocaml_output=$NEGATIVE_OUTPUT" -D "$define" >"$INVALID_LOG" 2>&1; then
		echo "The unsupported $define catch-local flow received rethrow authority" >&2
		exit 1
	fi
	if ! grep -Fq "a throw reached syntax after its exception-control family was rejected" "$INVALID_LOG"; then
		echo "The unsupported $define flow failed for an unexpected reason" >&2
		cat "$INVALID_LOG" >&2
		exit 1
	fi
done

echo "ENUM_CATCH_RETHROW:PASS rethrows=6 native_cases=9"
