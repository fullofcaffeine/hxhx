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

if (report.schemaVersion !== 26
	|| report.controlModel !== 'typed-ocaml-exact-int-return-control-v1'
	|| report.controlCount !== 6
	|| report.controls.length !== 6
	|| !sha256.test(report.controlRevision)) {
	fail('unexpected exact-Int control report schema, model, count, or revision')
}

const expectedByFunction = new Map([
	['branch', 1],
	['loop', 1],
	['nestedBlock', 1],
	['throughTry', 2],
	['nestedClosure', 1]
])
for (const [name, expectedCount] of expectedByFunction) {
	const decisions = report.controls.filter(control =>
		control.functionId.includes(`|function|${name}|`))
	if (decisions.length !== expectedCount) {
		fail(`expected ${expectedCount} sealed ${name} return decisions, got ${decisions.length}`)
	}
}
if (report.controls.some(control =>
	control.functionId.includes('|function|local|'))) {
	fail('the outer method control plan incorrectly claimed the nested function literal')
}

const ids = new Set()
for (const control of report.controls) {
	if (ids.has(control.id)
		|| control.kind !== 'return'
		|| control.effect !== 'exit-function'
		|| control.targetFunctionId !== control.functionId
		|| control.mechanism !== 'runtime-return-signal'
		|| control.runtimeCapabilityId !== 'hxhx-runtime:function-return-signal-v1'
		|| control.profileEligibility.join(',') !== 'metal,portable'
		|| control.proofId !== 'exact-int-early-return-control-v1'
		|| !control.reason
		|| !control.proofClaim
		|| !control.source.file
		|| control.source.min < 0
		|| control.source.max < control.source.min
		|| !rawSha256.test(control.programRevision)
		|| !bodyRevision.test(control.bodyRevision)
		|| control.pipelineRevision !== 'ocaml-function-plans-v26') {
		fail(`control decision ${control.id} has incomplete identity, target, proof, profile, source, or revision`)
	}
	const payload = control.payload
	if (payload.inputSemanticTypeId !== 'Int'
		|| payload.inputCarrierTypeId !== 'int'
		|| payload.inputRepresentationId !== 'representation:Int:internal-value'
		|| payload.signalCarrierTypeId !== 'Obj.t'
		|| payload.outputSemanticTypeId !== 'Int'
		|| payload.outputCarrierTypeId !== 'int'
		|| payload.outputRepresentationId !== 'representation:Int:internal-value'
		|| payload.conversion !== 'box-and-recover-exact-int'
		|| payload.proofId !== 'exact-int-early-return-control-v1'
		|| !payload.proofClaim) {
		fail(`control decision ${control.id} has an incomplete exact-Int payload crossing`)
	}
	ids.add(control.id)
}

for (const name of ['branch', 'loop', 'nestedBlock', 'throughTry']) {
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
		fail(`${name} did not hard-cut to the sealed exact-Int return mechanism`)
	}
}
const tryStart = source.indexOf('let throughTry =')
const tryEnd = source.indexOf('\nlet nestedClosure =', tryStart)
const tryBody = source.slice(tryStart, tryEnd)
if (!/HxRuntime\.Hx_return __ret_\d+ -> raise \(HxRuntime\.Hx_return __ret_\d+\)/.test(tryBody)) {
	fail('a source catch can intercept the private function-return signal')
}
const closureStart = source.indexOf('let nestedClosure =')
const closureEnd = source.indexOf('\nlet main =', closureStart)
const closureBody = source.slice(closureStart, closureEnd)
if (!closureBody.includes('let local = fun')
	|| !closureBody.includes('__fallback_result')
	|| !closureBody.includes('HxRuntime.Hx_return')
	|| !closureBody.includes(': int)')) {
	fail('the nested function literal was not kept on its independent legacy boundary while the outer exact-Int return used its sealed plan')
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
if (report.schemaVersion !== 11
	|| report.summary.valid !== true
	|| report.summary.controlCount !== 6
	|| report.lowering.controls.length !== 6
	|| report.lowering.scope !== 'typed-place-call-and-first-control-families') {
	throw new Error('public inspection did not expose the six validated exact-Int control decisions')
}
NODE

echo "REFLAXE_OCAML_EARLY_RETURN_CONTROL_FIXTURE:PASS controls=6"
