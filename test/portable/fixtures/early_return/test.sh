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

if (report.schemaVersion !== 27
	|| report.controlModel !== 'typed-ocaml-function-and-loop-control-v3'
	|| report.controlTargetModel !== 'typed-ocaml-lexical-loop-target-v1'
	|| report.controlCount !== report.controls.length
	|| report.controlTargetCount !== report.controlTargets.length
	|| !sha256.test(report.controlRevision)
	|| !sha256.test(report.controlTargetRevision)) {
	fail('unexpected function/loop control report schema, model, inventory, or revision')
}

const returnControls = report.controls.filter(control => control.kind === 'return')
if (returnControls.length !== 18) {
	fail(`expected 18 exact-value return decisions, got ${returnControls.length}`)
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
		control.functionId.includes(`|function|${name}|`))
	if (decisions.length !== expectedCount) {
		fail(`expected ${expectedCount} sealed ${name} return decisions, got ${decisions.length}`)
	}
}
if (returnControls.some(control =>
	control.functionId.includes('|function|local|'))) {
	fail('the outer method control plan incorrectly claimed the nested function literal')
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
		|| control.profileEligibility.join(',') !== 'metal,portable'
		|| control.proofId !== 'exact-value-early-return-control-v2'
		|| !control.reason
		|| !control.proofClaim
		|| !control.source.file
		|| control.source.min < 0
		|| control.source.max < control.source.min
		|| !rawSha256.test(control.programRevision)
		|| !bodyRevision.test(control.bodyRevision)
		|| control.pipelineRevision !== 'ocaml-function-plans-v29') {
		fail(`control decision ${control.id} has incomplete identity, target, proof, profile, source, or revision`)
	}
	const payload = control.payload
	const expectedCarrier = new Map([
		['Int', 'int'],
		['Bool', 'bool'],
		['String', 'string']
	]).get(payload.inputSemanticTypeId)
	if (!expectedCarrier
		|| payload.inputCarrierTypeId !== expectedCarrier
		|| payload.inputRepresentationId !== `representation:${payload.inputSemanticTypeId}:internal-value`
		|| payload.signalCarrierTypeId !== 'Obj.t'
		|| payload.outputSemanticTypeId !== payload.inputSemanticTypeId
		|| payload.outputCarrierTypeId !== expectedCarrier
		|| payload.outputRepresentationId !== payload.inputRepresentationId
		|| payload.conversion !== 'box-and-recover-exact-value'
		|| payload.proofId !== 'exact-value-early-return-control-v2'
		|| !payload.proofClaim) {
		fail(`control decision ${control.id} has an incomplete exact-value payload crossing`)
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
const closureEnd = source.indexOf('\nlet main =', closureStart)
const closureBody = source.slice(closureStart, closureEnd)
if (!closureBody.includes('let local = fun')
	|| !closureBody.includes('__fallback_result')
	|| !closureBody.includes('HxRuntime.Hx_return')
	|| !closureBody.includes(': int)')) {
	fail('the nested function literal was not kept on its independent legacy boundary while the outer exact-value return used its sealed plan')
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
if (report.schemaVersion !== 12
	|| report.summary.valid !== true
	|| report.summary.controlCount !== report.lowering.controls.length
	|| report.summary.controlTargetCount !== report.lowering.controlTargets.length
	|| report.lowering.controls.filter(control => control.kind === 'return').length !== 18
	|| report.lowering.scope !== 'typed-place-call-and-function-loop-control-families') {
	throw new Error('public inspection did not expose the 18 validated exact-value control decisions')
}
NODE

echo "REFLAXE_OCAML_EARLY_RETURN_CONTROL_FIXTURE:PASS controls=18"
