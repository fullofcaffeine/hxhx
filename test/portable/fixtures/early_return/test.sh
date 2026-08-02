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

if (report.schemaVersion !== 53
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v15'
	|| report.controlTargetModel !== 'typed-ocaml-lexical-loop-target-v1'
	|| report.controlCount !== report.controls.length
	|| report.controlTargetCount !== report.controlTargets.length
	|| !sha256.test(report.controlRevision)
	|| !sha256.test(report.controlTargetRevision)) {
	fail('unexpected function/loop control report schema, model, inventory, or revision')
}

const returnControls = report.controls.filter(control => control.kind === 'return')
if (returnControls.length !== 32) {
	fail(`expected 32 represented return decisions, including ordinary and nested Dynamic, catch, and loop paths, got ${returnControls.length}`)
}
const expectedByFunction = new Map([
	['branch', 1],
	['loop', 1],
	['nestedBlock', 1],
	['throughTry', 2],
	['boolBranch', 1],
	['stringThroughTry', 2],
	['nullableStringCarrier', 1],
	['dynamicBranch', 1],
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
	['nestedNullableBoolClosure', 'Null<Bool>'],
	['nestedDynamicClosure', 'Dynamic'],
	['nestedZeroArgumentClosure', 'Int']
])
for (const [functionName, semanticType] of representedNestedFunctions) {
	const decisions = returnControls.filter(control =>
		control.functionId.includes(`|function|${functionName}|`)
		&& control.functionId.includes('|nested-function|'))
	if (decisions.length !== 1 || decisions[0].payload.outputSemanticTypeId !== semanticType) {
		fail(`${functionName} did not seal one nested ${semanticType} return decision`)
	}
}
for (const functionName of ['nestedUnsupportedThrowClosure', 'nestedNominalClosure']) {
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
for (const [functionName, expectedCount] of [['nestedCatchClosure', 2], ['nestedThrowCatchClosure', 1]]) {
	const decisions = returnControls.filter(control =>
		control.functionId.includes(`|function|${functionName}|`)
		&& control.functionId.includes('|nested-function|'))
	if (decisions.length !== expectedCount) {
		fail(`${functionName} did not seal its ${expectedCount} nested return decisions`)
	}
}

const nestedThrows = report.controls.filter(control =>
	control.kind === 'throw'
	&& control.functionId.includes('|function|nestedThrowCatchClosure|')
	&& control.functionId.includes('|nested-function|'))
if (nestedThrows.length !== 1
	|| nestedThrows[0].payload?.inputSemanticTypeId !== 'Int'
	|| nestedThrows[0].payload?.inputCarrierTypeId !== 'int'
	|| nestedThrows[0].payload?.conversion !== 'repr-and-recover-exact-value'
	|| nestedThrows[0].proofId !== 'exact-value-throw-control-v1'
	|| nestedThrows[0].pipelineRevision !== 'ocaml-nested-function-plans-v6') {
	fail('nestedThrowCatchClosure did not seal its exact Int throw under the nested binding')
}
const nestedCatches = report.controlCatches.filter(catchChain =>
	catchChain.functionId.includes('|nested-function|')
	&& (catchChain.functionId.includes('|function|nestedCatchClosure|')
		|| catchChain.functionId.includes('|function|nestedThrowCatchClosure|')))
if (nestedCatches.length !== 2
	|| nestedCatches.some(catchChain =>
		catchChain.pipelineRevision !== 'ocaml-nested-function-plans-v6'
		|| catchChain.privateControlPolicy !== 'propagate-private-control-signals'
		|| catchChain.clauses.length !== 1)) {
	fail('the two nested catch chains are missing or do not preserve private control signals')
}
const intCatch = nestedCatches.find(catchChain => catchChain.functionId.includes('|function|nestedThrowCatchClosure|'))
if (intCatch?.clauses[0].semanticTypeId !== 'Int'
	|| intCatch.clauses[0].outputCarrierTypeId !== 'int'
	|| intCatch.clauses[0].matchPolicy !== 'exact-runtime-tag'
	|| intCatch.clauses[0].runtimeTag !== 'Int') {
	fail('nestedThrowCatchClosure did not seal the exact Int catch policy')
}

const nestedLoopTargets = report.controlTargets.filter(target =>
	target.functionId.includes('|function|nestedLoopClosure|')
	&& target.functionId.includes('|nested-function|'))
const nestedLoopTransfers = report.controls.filter(control =>
	(control.kind === 'break' || control.kind === 'continue')
	&& control.functionId.includes('|function|nestedLoopClosure|')
	&& control.functionId.includes('|nested-function|'))
const nestedLoopReturns = returnControls.filter(control =>
	control.functionId.includes('|function|nestedLoopClosure|')
	&& control.functionId.includes('|nested-function|'))
if (nestedLoopTargets.length !== 1
	|| nestedLoopTransfers.length !== 2
	|| nestedLoopReturns.length !== 1
	|| nestedLoopTransfers.filter(control => control.kind === 'break').length !== 1
	|| nestedLoopTransfers.filter(control => control.kind === 'continue').length !== 1
	|| nestedLoopTargets[0].pipelineRevision !== 'ocaml-nested-function-plans-v6'
	|| nestedLoopReturns[0].functionId !== nestedLoopTargets[0].functionId
	|| nestedLoopReturns[0].pipelineRevision !== nestedLoopTargets[0].pipelineRevision
	|| nestedLoopReturns[0].bodyRevision !== nestedLoopTargets[0].bodyRevision
	|| nestedLoopReturns[0].programRevision !== nestedLoopTargets[0].programRevision
	|| nestedLoopTransfers.some(control =>
		control.functionId !== nestedLoopTargets[0].functionId
		|| control.targetId !== nestedLoopTargets[0].id
		|| control.pipelineRevision !== nestedLoopTargets[0].pipelineRevision
		|| control.bodyRevision !== nestedLoopTargets[0].bodyRevision
		|| control.programRevision !== nestedLoopTargets[0].programRevision)) {
	fail('nestedLoopClosure did not seal one exact lexical loop with its break, continue, and return decisions')
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
			? control.pipelineRevision !== 'ocaml-nested-function-plans-v6'
			: control.pipelineRevision !== 'ocaml-function-plans-v66')) {
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
	const dynamicCarrier = control.proofId === 'dynamic-carrier-return-control-v1'
		&& payload.inputSemanticTypeId === 'Dynamic'
		&& payload.inputCarrierTypeId === 'Obj.t'
		&& payload.inputRepresentationId === 'representation:Dynamic:internal-value'
		&& payload.outputSemanticTypeId === 'Dynamic'
		&& payload.outputCarrierTypeId === 'Obj.t'
		&& payload.outputRepresentationId === payload.inputRepresentationId
		&& payload.conversion === 'preserve-dynamic-return-carrier'
		&& payload.proofId === 'dynamic-carrier-return-control-v1'
	if (payload.signalCarrierTypeId !== 'Obj.t'
		|| (!exactValue && !nullableInt && !nullableBool && !dynamicCarrier)
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
	['nestedNullableBoolClosure', 'Obj.t'],
	['nestedDynamicClosure', 'Obj.t'],
	['nestedZeroArgumentClosure', 'int']
]) {
	const start = source.indexOf(`let ${functionName} =`)
	const next = source.indexOf('\nlet ', start + 1)
	const body = source.slice(start, next)
	if (start < 0
		|| next < 0
		|| !body.includes('HxRuntime.Hx_return')
		|| body.includes('__fallback_result')
		|| body.includes('Obj.magic')
		|| (functionName === 'nestedZeroArgumentClosure' && !body.includes('let local = fun () ->'))
		|| !body.includes(`: ${expectedType}`)) {
		fail(`${functionName} did not consume its represented nested return plan`)
	}
}
const dynamicClosureStart = source.indexOf('let nestedDynamicClosure =')
const dynamicClosureEnd = source.indexOf('\nlet nestedZeroArgumentClosure =', dynamicClosureStart)
const dynamicClosureBody = source.slice(dynamicClosureStart, dynamicClosureEnd)
if (dynamicClosureStart < 0
	|| dynamicClosureEnd < 0
	|| !dynamicClosureBody.includes('HxRuntime.Hx_return early')
	|| !/HxRuntime\.Hx_return __ret_\d+ -> \(__ret_\d+ : Obj\.t\)/.test(dynamicClosureBody)
	|| dynamicClosureBody.includes('HxRuntime.Hx_return (Obj.repr')
	|| dynamicClosureBody.includes('Obj.obj')
	|| dynamicClosureBody.includes('Obj.magic')
	|| dynamicClosureBody.includes('__fallback_result')) {
	fail('nestedDynamicClosure did not preserve its existing Dynamic Obj.t carrier through the private return signal')
}
const dynamicBranchControl = returnControls.find(control =>
	control.functionId.includes('|function|dynamicBranch|')
	&& !control.functionId.includes('|nested-function|'))
const dynamicBranchStart = source.indexOf('let dynamicBranch =')
const dynamicBranchEnd = source.indexOf('\nlet ', dynamicBranchStart + 1)
const dynamicBranchBody = source.slice(dynamicBranchStart, dynamicBranchEnd)
if (dynamicBranchControl?.pipelineRevision !== 'ocaml-function-plans-v66'
	|| dynamicBranchControl.proofId !== 'dynamic-carrier-return-control-v1'
	|| dynamicBranchStart < 0
	|| dynamicBranchEnd < 0
	|| !dynamicBranchBody.includes('HxRuntime.Hx_return early')
	|| !/HxRuntime\.Hx_return __ret_\d+ -> \(__ret_\d+ : Obj\.t\)/.test(dynamicBranchBody)
	|| dynamicBranchBody.includes('HxRuntime.Hx_return (Obj.repr')
	|| dynamicBranchBody.includes('Obj.obj')
	|| dynamicBranchBody.includes('Obj.magic')
	|| dynamicBranchBody.includes('__fallback_result')) {
	fail('dynamicBranch did not preserve its existing Dynamic Obj.t carrier through the root v63 return plan')
}
for (const functionName of ['nestedUnsupportedThrowClosure', 'nestedNominalClosure']) {
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
for (const functionName of ['nestedCatchClosure', 'nestedThrowCatchClosure']) {
	const start = source.indexOf(`let ${functionName} =`)
	const next = source.indexOf('\nlet ', start + 1)
	const body = source.slice(start, next)
	if (start < 0
		|| next < 0
		|| !body.includes('HxRuntime.Hx_return')
		|| !body.includes('HxRuntime.Hx_exception')
		|| !body.includes('raise (HxRuntime.Hx_return')
		|| body.includes('__fallback_result')
		|| body.includes('Obj.magic')) {
		fail(`${functionName} did not consume its nested return and catch plan without legacy result recovery`)
	}
}
const throwCatchStart = source.indexOf('let nestedThrowCatchClosure =')
const throwCatchEnd = source.indexOf('\nlet nestedLoopClosure =', throwCatchStart)
const throwCatchBody = source.slice(throwCatchStart, throwCatchEnd)
if (!throwCatchBody.includes('HxType.hx_throw_typed_rtti (Obj.repr 21) ["Dynamic"]')
	|| !throwCatchBody.includes('HxRuntime.tags_has __exn_tags_')
	|| !throwCatchBody.includes('"Int"')) {
	fail('nestedThrowCatchClosure did not consume the planned exact Int throw and catch tags')
}
const loopClosureStart = source.indexOf('let nestedLoopClosure =')
const loopClosureEnd = source.indexOf('\nlet main =', loopClosureStart)
const loopClosureBody = source.slice(loopClosureStart, loopClosureEnd)
if (!loopClosureBody.includes('raise (HxRuntime.Hx_break)')
	|| !loopClosureBody.includes('| HxRuntime.Hx_break -> ()')
	|| !loopClosureBody.includes('raise (HxRuntime.Hx_continue)')
	|| !loopClosureBody.includes('| HxRuntime.Hx_continue -> ()')
	|| !loopClosureBody.includes('HxRuntime.Hx_return')
	|| loopClosureBody.includes('__fallback_result')
	|| loopClosureBody.includes('Obj.magic')) {
	fail('nestedLoopClosure did not consume its exact nested loop and return plan')
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
if (report.schemaVersion !== 31
	|| report.summary.valid !== true
	|| report.summary.controlCount !== report.lowering.controls.length
	|| report.summary.controlTargetCount !== report.lowering.controlTargets.length
	|| report.lowering.controls.filter(control => control.kind === 'return').length !== 32
	|| report.lowering.scope !== 'typed-place-anonymous-object-call-and-function-loop-throw-catch-control-families') {
	throw new Error('public inspection did not expose the 32 validated represented control decisions')
}
NODE

echo "REFLAXE_OCAML_EARLY_RETURN_CONTROL_FIXTURE:PASS controls=32"
