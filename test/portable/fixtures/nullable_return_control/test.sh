#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
REPORT_COPY="$(mktemp)"
INSPECTION_COPY="$(mktemp)"
TAMPER_INSPECTION="$(mktemp)"
UNSUPPORTED_OUTPUT="$(mktemp)"
trap 'rm -f "$REPORT_COPY" "$INSPECTION_COPY" "$TAMPER_INSPECTION" "$UNSUPPORTED_OUTPUT"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
	echo "Missing generated nullable-return source or lowering report" >&2
	exit 1
fi

node - "$SOURCE_FILE" "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const rawSha256 = /^[0-9a-f]{64}$/
const bodyRevision = /^[0-9]+:[0-9a-f]{64}$/

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 31
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v7'
	|| report.controlCount !== report.controls.length) {
	fail('unexpected nullable-return control report schema, model, or inventory')
}

const controls = report.controls.filter(control =>
	control.kind === 'return'
	&& control.functionId.startsWith('Main|Main|')
	&& control.mechanism === 'runtime-return-signal'
	&& control.payload?.conversion === 'preserve-nullable-carrier')
const expectedByFunction = new Map([
	['chooseInt', 'Null<Int>'],
	['chooseBool', 'Null<Bool>'],
	['preserveIntFallback', 'Null<Int>'],
	['preserveBoolFallback', 'Null<Bool>'],
	['intThroughTry', 'Null<Int>'],
	['boolThroughTry', 'Null<Bool>']
])
if (controls.length !== expectedByFunction.size)
	fail(`expected ${expectedByFunction.size} nullable-carrier return decisions, got ${controls.length}`)

const ids = new Set()
for (const [name, semanticType] of expectedByFunction) {
	const decisions = controls.filter(control =>
		control.functionId.includes(`|function|${name}|`))
	if (decisions.length !== 1)
		fail(`expected one sealed ${name} nullable return, got ${decisions.length}`)
	const control = decisions[0]
	const representation = `representation:${semanticType}:internal-value`
	if (ids.has(control.id)
		|| control.effect !== 'exit-function'
		|| control.targetKind !== 'function'
		|| control.targetId !== control.functionId
		|| control.payload.inputSemanticTypeId !== semanticType
		|| control.payload.outputSemanticTypeId !== semanticType
		|| control.payload.inputCarrierTypeId !== 'Obj.t'
		|| control.payload.signalCarrierTypeId !== 'Obj.t'
		|| control.payload.outputCarrierTypeId !== 'Obj.t'
		|| control.payload.inputRepresentationId !== representation
		|| control.payload.outputRepresentationId !== representation
		|| control.payload.proofId !== 'exact-nullable-carrier-early-return-control-v1'
		|| control.runtimeTags.length !== 0
		|| control.runtimeTagPolicy !== 'no-runtime-tags'
		|| control.runtimeCapabilityId !== 'hxhx-runtime:function-return-signal-v1'
		|| control.proofId !== 'exact-nullable-carrier-early-return-control-v1'
		|| control.profileEligibility.join(',') !== 'metal,portable'
		|| control.pipelineRevision !== 'ocaml-function-plans-v33'
		|| !rawSha256.test(control.programRevision)
		|| !bodyRevision.test(control.bodyRevision)
		|| !control.reason
		|| !control.proofClaim
		|| !control.source.file
		|| control.source.min < 0
		|| control.source.max < control.source.min) {
		fail(`nullable return ${control.id} has incomplete carrier ownership metadata`)
	}
	ids.add(control.id)
}

function functionBody(name, nextName) {
	const start = source.indexOf(`let ${name} =`)
	const end = source.indexOf(`\nlet ${nextName} =`, start)
	if (start < 0 || end < 0)
		fail(`generated source is missing ${name} or ${nextName}`)
	return source.slice(start, end)
}

for (const [name, next, earlyValue, boxesFallback] of [
	['chooseInt', 'chooseBool', 'value', true],
	['chooseBool', 'preserveIntFallback', 'value', true],
	['preserveIntFallback', 'preserveBoolFallback', 'early', false],
	['preserveBoolFallback', 'printInt', 'early', false],
	['intThroughTry', 'boolThroughTry', 'value', true],
	['boolThroughTry', 'main', 'value', true]
]) {
	const body = functionBody(name, next)
	if (!body.includes(`raise (HxRuntime.Hx_return ${earlyValue})`)
		|| !body.includes('| HxRuntime.Hx_return __ret_')
		|| !body.includes('-> (__ret_')
		|| !body.includes(': Obj.t)')
		|| (boxesFallback !== body.includes('try Obj.repr'))
		|| body.includes(`Hx_return (Obj.repr ${earlyValue})`)
		|| body.includes('Obj.obj __ret_')
		|| body.includes('Obj.magic __ret_')
		|| body.includes('Obj.repr (try')) {
		fail(`${name} did not preserve its exact nullable carrier through the private return boundary`)
	}
}

for (const [name, next] of [
	['intThroughTry', 'boolThroughTry'],
	['boolThroughTry', 'main']
]) {
	const body = functionBody(name, next)
	if (!body.includes('| HxRuntime.Hx_return __ret_')
		|| !body.includes('-> raise (HxRuntime.Hx_return __ret_')) {
		fail(`a source catch can intercept ${name}'s private nullable-return signal`)
	}
}
NODE

cp "$REPORT_FILE" "$REPORT_COPY"
haxe build.hxml
if ! cmp -s "$REPORT_COPY" "$REPORT_FILE"; then
	echo "The exact same typed program produced a different nullable-return report" >&2
	diff -u "$REPORT_COPY" "$REPORT_FILE" >&2 || true
	exit 1
fi

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$INSPECTION_COPY"

node - "$INSPECTION_COPY" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const controls = report.lowering.controls.filter(control =>
	control.kind === 'return'
	&& control.functionId.startsWith('Main|Main|')
	&& control.payload?.conversion === 'preserve-nullable-carrier')
if (report.schemaVersion !== 16
	|| report.summary.valid !== true
	|| report.summary.controlCount !== report.lowering.controls.length
	|| controls.length !== 6
	|| controls.some(control =>
		control.payload.inputCarrierTypeId !== 'Obj.t'
		|| control.payload.outputCarrierTypeId !== 'Obj.t'
		|| control.proofId !== 'exact-nullable-carrier-early-return-control-v1')
	|| report.lowering.scope !== 'typed-place-call-and-function-loop-throw-catch-control-families') {
	throw new Error('public inspection did not expose the 6 validated nullable-carrier returns')
}
NODE

node - "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const control = report.controls.find(candidate =>
	candidate.kind === 'return' && candidate.payload?.conversion === 'preserve-nullable-carrier')
if (!control)
	throw new Error('missing nullable-carrier return to corrupt')
control.payload.conversion = 'box-and-recover-exact-value'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$TAMPER_INSPECTION" 2>&1; then
	echo "Public inspection accepted a nullable return with an exact-value boxing conversion" >&2
	exit 1
fi
if ! grep -q "exact-value or nullable-carrier payload crossing" "$TAMPER_INSPECTION"; then
	echo "Public inspection rejected the corrupt nullable return without an actionable reason" >&2
	cat "$TAMPER_INSPECTION" >&2
	exit 1
fi
cp "$REPORT_COPY" "$REPORT_FILE"

rm -rf unsupported_out
if haxe unsupported.hxml >"$UNSUPPORTED_OUTPUT" 2>&1; then
	echo "Nested Int-to-Null<Int> return conversion unexpectedly compiled" >&2
	exit 1
fi
if ! grep -q "ocaml-call:result-control-unsealed" "$UNSUPPORTED_OUTPUT"; then
	echo "Unsupported nested nullable conversion failed without the expected result-control diagnostic" >&2
	cat "$UNSUPPORTED_OUTPUT" >&2
	exit 1
fi
if [ -f unsupported_out/Unsupported.ml ] || [ -f unsupported_out/ocaml_lowering_report.json ]; then
	echo "Unsupported nested nullable conversion published partial source or lowering evidence" >&2
	exit 1
fi

echo "REFLAXE_OCAML_NULLABLE_RETURN_CONTROL_FIXTURE:PASS controls=6"
