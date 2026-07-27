#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
REPORT_COPY="$(mktemp)"
INSPECTION_COPY="$(mktemp)"
TAMPER_INSPECTION="$(mktemp)"
trap 'rm -f "$REPORT_COPY" "$INSPECTION_COPY" "$TAMPER_INSPECTION"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
	echo "Missing generated Void-return source or lowering report" >&2
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

if (report.schemaVersion !== 37
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v13'
	|| report.controlCount !== report.controls.length) {
	fail('unexpected Void-return control report schema, model, or inventory')
}

const controls = report.controls.filter(control =>
	control.kind === 'return'
	&& control.functionId.startsWith('Main|Main|')
	&& control.mechanism === 'runtime-void-return-signal')
const expectedByFunction = new Map([
	['branch', 1],
	['loop', 1],
	['throughTry', 1],
	['fromCatch', 1]
])
if (controls.length !== 4)
	fail(`expected 4 effect-only Void return decisions, got ${controls.length}`)
for (const [name, expectedCount] of expectedByFunction) {
	const decisions = controls.filter(control =>
		control.functionId.includes(`|function|${name}|`))
	if (decisions.length !== expectedCount)
		fail(`expected ${expectedCount} sealed ${name} Void return, got ${decisions.length}`)
}
if (controls.some(control => control.functionId.includes('|function|local|')))
	fail('the outer function plan incorrectly claimed the nested function literal')

const ids = new Set()
for (const control of controls) {
	if (ids.has(control.id)
		|| control.effect !== 'exit-function'
		|| control.targetKind !== 'function'
		|| control.targetId !== control.functionId
		|| control.payload !== null
		|| control.runtimeTags.length !== 0
		|| control.runtimeTagPolicy !== 'no-runtime-tags'
		|| control.runtimeCapabilityId !== 'hxhx-runtime:function-void-return-signal-v1'
		|| control.proofId !== 'effect-only-void-early-return-control-v1'
		|| control.profileEligibility.join(',') !== 'metal,portable'
		|| control.pipelineRevision !== 'ocaml-function-plans-v39'
		|| !rawSha256.test(control.programRevision)
		|| !bodyRevision.test(control.bodyRevision)
		|| !control.reason
		|| !control.proofClaim
		|| !control.source.file
		|| control.source.min < 0
		|| control.source.max < control.source.min) {
		fail(`Void return ${control.id} has incomplete effect-only ownership metadata`)
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

for (const [name, next] of [
	['branch', 'loop'],
	['loop', 'throughTry'],
	['throughTry', 'fromCatch'],
	['fromCatch', 'nestedClosure']
]) {
	const body = functionBody(name, next)
	if (!body.includes('raise (HxRuntime.Hx_return_void)')
		|| !body.includes('| HxRuntime.Hx_return_void -> ()')
		|| body.includes('Hx_return (Obj.repr ())')) {
		fail(`${name} did not mechanically consume its payloadless return signal and boundary`)
	}
}

for (const name of ['throughTry', 'fromCatch']) {
	const next = name === 'throughTry' ? 'fromCatch' : 'nestedClosure'
	const body = functionBody(name, next)
	if (!body.includes('| HxRuntime.Hx_return_void -> raise (HxRuntime.Hx_return_void)'))
		fail(`a source catch can intercept ${name}'s private Void-return signal`)
}

const closureBody = functionBody('nestedClosure', 'main')
if (!closureBody.includes('let local = fun')
	|| !closureBody.includes('"outer"')) {
	fail('the nested anonymous function did not keep an independent return boundary')
}
NODE

cp "$REPORT_FILE" "$REPORT_COPY"
haxe build.hxml
if ! cmp -s "$REPORT_COPY" "$REPORT_FILE"; then
	echo "The exact same typed program produced a different Void-return report" >&2
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
	&& control.mechanism === 'runtime-void-return-signal')
if (report.schemaVersion !== 22
	|| report.summary.valid !== true
	|| report.summary.controlCount !== report.lowering.controls.length
	|| controls.length !== 4
	|| controls.some(control => control.payload !== null)
	|| report.lowering.scope !== 'typed-place-call-and-function-loop-throw-catch-control-families') {
	throw new Error('public inspection did not expose the 4 validated effect-only Void returns')
}
NODE

node - "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const control = report.controls.find(candidate =>
	candidate.kind === 'return' && candidate.mechanism === 'runtime-void-return-signal')
if (!control)
	throw new Error('missing effect-only Void return to corrupt')
control.mechanism = 'runtime-return-signal'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$TAMPER_INSPECTION" 2>&1; then
	echo "Public inspection accepted a payloadless return with a value-return mechanism" >&2
	exit 1
fi
if ! grep -q "exact-value return capability or payload" "$TAMPER_INSPECTION"; then
	echo "Public inspection rejected the corrupt Void return without an actionable reason" >&2
	cat "$TAMPER_INSPECTION" >&2
	exit 1
fi
cp "$REPORT_COPY" "$REPORT_FILE"

echo "REFLAXE_OCAML_VOID_RETURN_CONTROL_FIXTURE:PASS controls=4"
