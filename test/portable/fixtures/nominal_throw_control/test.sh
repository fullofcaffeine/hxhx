#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
FIRST_REPORT="$(mktemp)"
INSPECTION_REPORT="$(mktemp)"
INVALID_THROW_LOG="$(mktemp)"
INVALID_CATCH_LOG="$(mktemp)"
INVALID_THROW_OUTPUT="out-invalid-nominal-throw-$$"
INVALID_CATCH_OUTPUT="out-invalid-nominal-catch-$$"
trap 'rm -f "$FIRST_REPORT" "$INSPECTION_REPORT" "$INVALID_THROW_LOG" "$INVALID_CATCH_LOG"; rm -rf "$INVALID_THROW_OUTPUT" "$INVALID_CATCH_OUTPUT"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
	echo "Missing generated nominal throw/catch source or lowering report" >&2
	exit 1
fi

node - "$SOURCE_FILE" "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const sha256 = /^sha256:[0-9a-f]{64}$/

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 57
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v18'
	|| report.controlCatchModel !== 'typed-ocaml-represented-value-catch-chain-v3'
	|| report.controlCatchCount !== report.controlCatches.length
	|| report.controlCatchCount !== 4) {
	fail('unexpected nominal throw/catch report schema, model, or inventory')
}

const representation = report.representations.find(item =>
	item.id === 'representation:Box:internal-value')
if (representation == null
	|| representation.semanticTypeId !== 'Box'
	|| representation.carrierTypeId !== 'box_t'
	|| representation.domain !== 'internal-value'
	|| representation.boxingPolicy !== 'nullable-nominal-record-carrier'
	|| representation.nullPolicy !== 'runtime-sentinel'
	|| representation.nominalTargetModuleName !== 'Main'
	|| representation.nominalTargetTypeName !== 'box_t'
	|| !sha256.test(representation.nominalLayoutRevision)
	|| representation.proof?.id !== `whole-program-monomorphic-nominal-record-v1:${representation.nominalLayoutRevision}`) {
	fail('Box is not sealed as the expected nullable nominal record')
}

const throws = report.controls.filter(control =>
	control.kind === 'throw'
	&& control.payload?.inputSemanticTypeId === 'Box')
const throwFunctions = ['directCase', 'nullCase', 'rethrowCase', 'throwFresh']
if (throws.length !== throwFunctions.length) {
	fail(`expected ${throwFunctions.length} nominal throw decisions, got ${throws.length}`)
}
for (const functionName of throwFunctions) {
	const control = throws.find(item =>
		item.functionId.includes(`|function|${functionName}|`))
	const payload = control?.payload
	const nominal = payload?.nominalRepresentation
	if (control == null
		|| control.pipelineRevision !== 'ocaml-function-plans-v70'
		|| control.proofId !== 'exact-monomorphic-class-throw-control-v1'
		|| control.runtimeTags.join(',') !== 'Dynamic'
		|| control.runtimeTagPolicy !== 'merge-dynamic-with-exact-runtime-value'
		|| payload?.conversion !== 'box-nominal-throw-carrier'
		|| payload.inputCarrierTypeId !== representation.carrierTypeId
		|| payload.inputRepresentationId !== representation.id
		|| payload.outputCarrierTypeId !== representation.carrierTypeId
		|| payload.outputRepresentationId !== representation.id
		|| payload.signalCarrierTypeId !== 'Obj.t'
		|| payload.proofId !== control.proofId
		|| nominal?.targetModuleName !== representation.nominalTargetModuleName
		|| nominal?.targetTypeName !== representation.nominalTargetTypeName
		|| nominal?.layoutRevision !== representation.nominalLayoutRevision
		|| nominal?.representationProofId !== representation.proof.id) {
		fail(`${functionName} did not bind its throw to the exact Box representation and Dynamic-only static tags`)
	}
}

let nominalClauseCount = 0
for (const chain of report.controlCatches) {
	if (chain.proofId !== 'represented-value-catch-control-v3'
		|| chain.pipelineRevision !== 'ocaml-function-plans-v70') {
		fail(`catch chain ${chain.id} does not use the represented-value proof`)
	}
	for (const clause of chain.clauses) {
		if (clause.semanticTypeId === 'Box') {
			nominalClauseCount++
			const nominal = clause.nominalRepresentation
			if (clause.matchPolicy !== 'exact-runtime-tag'
				|| clause.runtimeTag !== 'Box'
				|| clause.outputCarrierTypeId !== representation.carrierTypeId
				|| clause.outputRepresentationId !== representation.id
				|| clause.conversion !== 'recover-nominal-value'
				|| clause.proofId !== chain.proofId
				|| nominal?.targetModuleName !== representation.nominalTargetModuleName
				|| nominal?.targetTypeName !== representation.nominalTargetTypeName
				|| nominal?.layoutRevision !== representation.nominalLayoutRevision
				|| nominal?.representationProofId !== representation.proof.id) {
				fail(`Box catch clause ${clause.id} is not bound to the sealed nominal layout`)
			}
		} else if (clause.nominalRepresentation != null) {
			fail(`non-nominal catch clause ${clause.id} unexpectedly carries a class-layout proof`)
		}
	}
}
if (nominalClauseCount !== 4) {
	fail(`expected four Box catch clauses, got ${nominalClauseCount}`)
}

const plannedThrows = source.match(/HxType\.hx_throw_typed_rtti \(Obj\.repr [^)]+\) \["Dynamic"\]/g) ?? []
if (plannedThrows.length < 4
	|| source.includes('["Dynamic"; "Box"]')
	|| !/HxRuntime\.tags_has __exn_tags_\d+ "Box" then let caught = \(Obj\.obj __exn_v_\d+ : box_t\)/.test(source)) {
	fail('generated OCaml did not mechanically consume the Dynamic-only throw tags and nominal catch recovery')
}
NODE

cp "$REPORT_FILE" "$FIRST_REPORT"
haxe build.hxml
if ! cmp -s "$FIRST_REPORT" "$REPORT_FILE"; then
	echo "The same typed program produced a different nominal throw/catch report" >&2
	diff -u "$FIRST_REPORT" "$REPORT_FILE" >&2 || true
	exit 1
fi

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$INSPECTION_REPORT"

node - "$INSPECTION_REPORT" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const nominalClauses = report.lowering.controlCatches.flatMap(chain => chain.clauses)
	.filter(clause => clause.semanticTypeId === 'Box')
if (report.schemaVersion !== 35
	|| report.summary.valid !== true
	|| report.summary.controlCatchCount !== 4
	|| nominalClauses.length !== 4
	|| nominalClauses.some(clause =>
		clause.conversion !== 'recover-nominal-value'
		|| clause.nominalRepresentation?.targetTypeName !== 'box_t')) {
	throw new Error('public inspection did not validate the nominal throw/catch decisions')
}
NODE

cp -R out "$INVALID_THROW_OUTPUT"
node - "$INVALID_THROW_OUTPUT/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const control = report.controls.find(item =>
	item.payload?.conversion === 'box-nominal-throw-carrier')
if (control?.payload?.nominalRepresentation == null)
	throw new Error('missing nominal throw proof to corrupt')
control.payload.nominalRepresentation.layoutRevision = `sha256:${'0'.repeat(64)}`
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision \
	"$INVALID_THROW_OUTPUT/ocaml_lowering_report.json"
if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output "$INVALID_THROW_OUTPUT" --require-lowering --json \
	>"$INVALID_THROW_LOG" 2>&1; then
	echo "The inspector accepted a nominal throw bound to a stale class layout" >&2
	exit 1
fi
if ! grep -Fq "invalid represented Haxe exception crossing" "$INVALID_THROW_LOG"; then
	echo "The inspector rejected the stale nominal throw for an unexpected reason" >&2
	cat "$INVALID_THROW_LOG" >&2
	exit 1
fi

cp -R out "$INVALID_CATCH_OUTPUT"
node - "$INVALID_CATCH_OUTPUT/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const clause = report.controlCatches.flatMap(chain => chain.clauses)
	.find(item => item.conversion === 'recover-nominal-value')
if (clause?.nominalRepresentation == null)
	throw new Error('missing nominal catch proof to corrupt')
clause.nominalRepresentation.layoutRevision = `sha256:${'0'.repeat(64)}`
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision \
	"$INVALID_CATCH_OUTPUT/ocaml_lowering_report.json"
if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output "$INVALID_CATCH_OUTPUT" --require-lowering --json \
	>"$INVALID_CATCH_LOG" 2>&1; then
	echo "The inspector accepted a nominal catch bound to a stale class layout" >&2
	exit 1
fi
if ! grep -Fq "Monomorphic-class control catch clause" "$INVALID_CATCH_LOG"; then
	echo "The inspector rejected the stale nominal catch for an unexpected reason" >&2
	cat "$INVALID_CATCH_LOG" >&2
	exit 1
fi

echo "NOMINAL_THROW_CONTROL:PASS throws=4 class_catches=4 null_dynamic_only=1"
