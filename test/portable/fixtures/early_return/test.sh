#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
REPORT_COPY="$(mktemp)"
INSPECTION_COPY="$(mktemp)"
trap 'rm -f "$REPORT_COPY" "$INSPECTION_COPY"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
	echo "Missing generated early-return source or lowering report" >&2
	exit 1
fi

node - "$SOURCE_FILE" "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const sha256 = /^sha256:[0-9a-f]{64}$/
const rawSha256 = /^[0-9a-f]{64}$/
const bodyRevision = /^[0-9]+:[0-9a-f]{64}$/

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 50
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v15'
	|| report.controlTargetModel !== 'typed-ocaml-lexical-loop-target-v1'
	|| report.controlCount !== report.controls.length
	|| report.controlTargetCount !== report.controlTargets.length
	|| !sha256.test(report.controlRevision)
	|| !sha256.test(report.controlTargetRevision)) {
	fail('unexpected function/loop control report schema, model, inventory, or revision')
}

const returnControls = report.controls.filter(control => control.kind === 'return')
if (returnControls.length !== 25) {
	fail(`expected 25 represented return decisions, including seven nested function literals, got ${returnControls.length}`)
}
const expectedByFunction = new Map([
	['branch', 1],
	['loop', 1],
	['nestedBlock', 1],
	['throughTry', 2],
	['boolBranch', 1],
	['stringThroughTry', 2],
	['nullableStringCarrier', 1],
	['nestedClosure', 1]
])
for (const [name, expectedCount] of expectedByFunction) {
	const decisions = returnControls.filter(control =>
		control.functionId.includes(`|function|${name}|`)
		&& !control.functionId.includes('|nested-function|'))
	if (decisions.length !== expectedCount) {
		fail(`expected ${expectedCount} sealed ${name} return decisions, got ${decisions.length}`)
	}
}
if (returnControls.some(control =>
	control.functionId.includes('|function|local|'))) {
	fail('the outer method control plan incorrectly claimed the nested function literal')
}
const nestedFunctionControls = returnControls.filter(control =>
	control.functionId.includes('|function|nestedClosure|')
	&& control.functionId.includes('|nested-function|'))
if (nestedFunctionControls.length !== 1) {
	fail(`expected one independently sealed nested-function return decision, got ${nestedFunctionControls.length}`)
}
const representedNestedFunctions = new Map([
	['nestedBoolClosure', 'Bool'],
	['nestedStringClosure', 'String'],
	['nestedNullableIntClosure', 'Null<Int>'],
	['nestedNullableBoolClosure', 'Null<Bool>']
])
for (const [functionName, semanticType] of representedNestedFunctions) {
	const decisions = returnControls.filter(control =>
		control.functionId.includes(`|function|${functionName}|`)
		&& control.functionId.includes('|nested-function|'))
	if (decisions.length !== 1 || decisions[0].payload.outputSemanticTypeId !== semanticType) {
		fail(`${functionName} did not seal one nested ${semanticType} return decision`)
	}
}
for (const functionName of ['nestedDynamicClosure', 'nestedZeroArgumentClosure', 'nestedUnsupportedThrowClosure', 'nestedNominalClosure']) {
	if (returnControls.some(control =>
		control.functionId.includes(`|function|${functionName}|`)
		&& control.functionId.includes('|nested-function|'))) {
		fail(`${functionName} crossed its explicit nested-function deferral boundary`)
	}
}
const deepNestedFunctionControls = returnControls.filter(control =>
	control.functionId.includes('|function|deepNestedClosure|')
	&& control.functionId.includes('|nested-function|'))
if (deepNestedFunctionControls.length !== 2
	|| !deepNestedFunctionControls.some(control =>
		control.functionId.split('|nested-function|').length - 1 === 2)) {
	fail('the two-level closure did not preserve an independently sealed child under its admitted nested parent')
}
if (returnControls.some(control =>
	control.functionId.includes('|function|nestedCatchClosure|')
	&& control.functionId.includes('|nested-function|'))) {
	fail('the first return-only nested slice incorrectly admitted a function containing try/catch')
}

const ids = new Set()
for (const control of returnControls) {
	if (ids.has(control.id)
		|| control.kind !== 'return'
		|| control.effect !== 'exit-function'
		|| control.targetKind !== 'function'
		|| control.targetId !== control.functionId
		|| control.mechanism !== 'runtime-return-signal'
		|| control.runtimeCapabilityId !== 'hxhx-runtime:function-return-signal-v1'
		|| control.runtimeTags.length !== 0
		|| control.runtimeTagPolicy !== 'no-runtime-tags'
		|| control.profileEligibility.join(',') !== 'metal,portable'
		|| !control.reason
		|| !control.proofClaim
		|| !control.source.file
		|| control.source.min < 0
		|| control.source.max < control.source.min
		|| !rawSha256.test(control.programRevision)
		|| !bodyRevision.test(control.bodyRevision)
		|| (control.functionId.includes('|nested-function|')
			? control.pipelineRevision !== 'ocaml-nested-function-plans-v2'
			: control.pipelineRevision !== 'ocaml-function-plans-v62')) {
		fail(`control decision ${control.id} has incomplete identity, target, proof, profile, source, or revision`)
	}
	const payload = control.payload
	const exactCarrier = new Map([
		['Int', 'int'],
		['Bool', 'bool'],
		['String', 'string']
	]).get(payload.inputSemanticTypeId)
	const exactValue = exactCarrier != null
		&& control.proofId === 'exact-value-early-return-control-v2'
		&& payload.inputCarrierTypeId === exactCarrier
		&& payload.inputRepresentationId === `representation:${payload.inputSemanticTypeId}:internal-value`
		&& payload.outputSemanticTypeId === payload.inputSemanticTypeId
		&& payload.outputCarrierTypeId === exactCarrier
		&& payload.outputRepresentationId === payload.inputRepresentationId
		&& payload.conversion === 'box-and-recover-exact-value'
		&& payload.proofId === 'exact-value-early-return-control-v2'
	const nullableInt = control.proofId === 'exact-int-to-nullable-early-return-control-v1'
		&& payload.inputSemanticTypeId === 'Int'
		&& payload.inputCarrierTypeId === 'int'
		&& payload.inputRepresentationId === 'representation:Int:internal-value'
		&& payload.outputSemanticTypeId === 'Null<Int>'
		&& payload.outputCarrierTypeId === 'Obj.t'
		&& payload.outputRepresentationId === 'representation:Null<Int>:internal-value'
		&& payload.conversion === 'box-exact-int-to-nullable-carrier'
		&& payload.proofId === 'exact-int-to-nullable-early-return-control-v1'
	const nullableBool = control.proofId === 'exact-bool-to-nullable-early-return-control-v1'
		&& payload.inputSemanticTypeId === 'Bool'
		&& payload.inputCarrierTypeId === 'bool'
		&& payload.inputRepresentationId === 'representation:Bool:internal-value'
		&& payload.outputSemanticTypeId === 'Null<Bool>'
		&& payload.outputCarrierTypeId === 'Obj.t'
		&& payload.outputRepresentationId === 'representation:Null<Bool>:internal-value'
		&& payload.conversion === 'box-exact-bool-to-nullable-carrier'
		&& payload.proofId === 'exact-bool-to-nullable-early-return-control-v1'
	if (payload.signalCarrierTypeId !== 'Obj.t'
		|| (!exactValue && !nullableInt && !nullableBool)
		|| !payload.proofClaim) {
		fail(`control decision ${control.id} has an incomplete represented return payload crossing`)
	}
	ids.add(control.id)
}

for (const name of ['branch', 'loop', 'nestedBlock', 'throughTry', 'boolBranch', 'stringThroughTry', 'nullableStringCarrier']) {
	const start = source.indexOf(`let ${name} =`)
	const next = source.indexOf('\nlet ', start + 1)
	if (start < 0 || next < 0) {
		fail(`generated source is missing function ${name}`)
	}
	const body = source.slice(start, next)
	if (!body.includes('HxRuntime.Hx_return')
		|| !body.includes('Obj.repr')
		|| !body.includes('Obj.obj')
		|| body.includes('__fallback_result')
		|| body.includes('Obj.magic')) {
		fail(`${name} did not hard-cut to the sealed exact-value return mechanism`)
	}
}
const tryStart = source.indexOf('let throughTry =')
const tryEnd = source.indexOf('\nlet nestedClosure =', tryStart)
const tryBody = source.slice(tryStart, tryEnd)
if (!/HxRuntime\.Hx_return __ret_\d+ -> raise \(HxRuntime\.Hx_return __ret_\d+\)/.test(tryBody)) {
	fail('a source catch can intercept the private function-return signal')
}
const stringTryStart = source.indexOf('let stringThroughTry =')
const stringTryEnd = source.indexOf('\nlet nestedClosure =', stringTryStart)
const stringTryBody = source.slice(stringTryStart, stringTryEnd)
if (!/HxRuntime\.Hx_return __ret_\d+ -> raise \(HxRuntime\.Hx_return __ret_\d+\)/.test(stringTryBody)
	|| !/Obj\.obj __ret_\d+ : string/.test(stringTryBody)) {
	fail('the exact-String try boundary does not rethrow private control before recovering its sealed string carrier')
}
const boolStart = source.indexOf('let boolBranch =')
const boolEnd = source.indexOf('\nlet stringThroughTry =', boolStart)
const boolBody = source.slice(boolStart, boolEnd)
if (!/Obj\.obj __ret_\d+ : bool/.test(boolBody)) {
	fail('the exact-Bool boundary did not recover its sealed bool carrier')
}
const nullableStringStart = source.indexOf('let nullableStringCarrier =')
const nullableStringEnd = source.indexOf('\nlet nestedClosure =', nullableStringStart)
const nullableStringBody = source.slice(nullableStringStart, nullableStringEnd)
if (!nullableStringBody.includes('Obj.repr (HxString.hx_null_string)')
	|| !/Obj\.obj __ret_\d+ : string/.test(nullableStringBody)) {
	fail('the exact-String boundary did not preserve the existing runtime null-sentinel carrier')
}
const closureStart = source.indexOf('let nestedClosure =')
const closureEnd = source.indexOf('\nlet nestedBoolClosure =', closureStart)
const closureBody = source.slice(closureStart, closureEnd)
if (!closureBody.includes('let local = fun')
	|| !closureBody.includes('HxRuntime.Hx_return')
	|| !closureBody.includes('Obj.repr')
	|| !closureBody.includes('Obj.obj')
	|| closureBody.includes('__fallback_result')
	|| closureBody.includes('Obj.magic')
	|| !closureBody.includes(': int)')) {
	fail('the nested function literal did not consume its independent exact-Int return plan')
}
for (const [functionName, expectedType] of [
	['nestedBoolClosure', 'bool'],
	['nestedStringClosure', 'string'],
	['nestedNullableIntClosure', 'Obj.t'],
	['nestedNullableBoolClosure', 'Obj.t']
]) {
	const start = source.indexOf(`let ${functionName} =`)
	const next = source.indexOf('\nlet ', start + 1)
	const body = source.slice(start, next)
	if (start < 0
		|| next < 0
		|| !body.includes('HxRuntime.Hx_return')
		|| body.includes('__fallback_result')
		|| body.includes('Obj.magic')
		|| !body.includes(`: ${expectedType}`)) {
		fail(`${functionName} did not consume its represented nested return plan`)
	}
}
for (const functionName of ['nestedDynamicClosure', 'nestedZeroArgumentClosure', 'nestedUnsupportedThrowClosure', 'nestedNominalClosure']) {
	const start = source.indexOf(`let ${functionName} =`)
	const next = source.indexOf('\nlet ', start + 1)
	const body = source.slice(start, next)
	if (start < 0
		|| next < 0
		|| !body.includes('HxRuntime.Hx_return')
		|| !body.includes('__fallback_result')
		|| !body.includes('Obj.magic')) {
		fail(`${functionName} did not remain on its explicit legacy nested-return path`)
	}
}
const deepClosureStart = source.indexOf('let deepNestedClosure =')
const deepClosureEnd = source.indexOf('\nlet nestedCatchClosure =', deepClosureStart)
const deepClosureBody = source.slice(deepClosureStart, deepClosureEnd)
if ((deepClosureBody.match(/HxRuntime\.Hx_return/g) ?? []).length < 4
	|| !deepClosureBody.includes('Obj.repr')
	|| !deepClosureBody.includes('Obj.obj')
	|| deepClosureBody.includes('__fallback_result')
	|| deepClosureBody.includes('Obj.magic')) {
	fail('the two-level nested functions did not consume their separate exact-Int return plans')
}
NODE

cp "$REPORT_FILE" "$REPORT_COPY"
haxe build.hxml
if ! cmp -s "$REPORT_COPY" "$REPORT_FILE"; then
	echo "The exact same typed program produced a different lowering report" >&2
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
if (report.schemaVersion !== 30
	|| report.summary.valid !== true
	|| report.summary.controlCount !== report.lowering.controls.length
	|| report.summary.controlTargetCount !== report.lowering.controlTargets.length
	|| report.lowering.controls.filter(control => control.kind === 'return').length !== 25
	|| report.lowering.scope !== 'typed-place-anonymous-object-call-and-function-loop-throw-catch-control-families') {
	throw new Error('public inspection did not expose the 25 validated represented control decisions')
}
NODE

echo "REFLAXE_OCAML_EARLY_RETURN_CONTROL_FIXTURE:PASS controls=25"
