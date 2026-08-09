#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
REPORT_COPY="$(mktemp)"
MANIFEST_FILE="out/ocaml_artifact_manifest.json"
MANIFEST_COPY="$(mktemp)"
INSPECTION_COPY="$(mktemp)"
TAMPER_INSPECTION="$(mktemp)"
trap 'rm -f "$REPORT_COPY" "$MANIFEST_COPY" "$INSPECTION_COPY" "$TAMPER_INSPECTION"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ] || [ ! -f "$MANIFEST_FILE" ]; then
	echo "Missing generated loop-control source or lowering report" >&2
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

if (report.schemaVersion !== 69
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v21'
	|| report.controlTargetModel !== 'typed-ocaml-lexical-loop-target-v1'
	|| report.controlCount !== report.controls.length
	|| report.controlTargetCount !== report.controlTargets.length
	|| !sha256.test(report.controlRevision)
	|| !sha256.test(report.controlTargetRevision)) {
	fail('unexpected function/loop control report schema, model, inventory, or revision')
}

const mainTargets = report.controlTargets.filter(target =>
	target.functionId.includes('Main|') && !target.functionId.includes('|function|local|'))
const mainTransfers = report.controls.filter(control =>
	control.targetKind === 'loop'
	&& control.functionId.includes('Main|')
	&& !control.functionId.includes('|function|local|'))
if (mainTargets.length !== 7 || mainTransfers.length !== 12) {
	fail(`expected 7 Main loop targets and 12 Main transfers, got ${mainTargets.length} and ${mainTransfers.length}`)
}
if (report.controls.some(control => control.functionId.includes('|function|local|'))) {
	fail('the outer function plan incorrectly claimed a nested function literal transfer')
}

const targetById = new Map(mainTargets.map(target => [target.id, target]))
const expectedTransfers = new Map([
	['nestedLoops', 3],
	['doWhileContinue', 1],
	['throughTry', 2],
	['voidLoop', 2],
	['floatLoop', 2],
	['nestedFunction', 2]
])
for (const [name, expectedCount] of expectedTransfers) {
	const decisions = mainTransfers.filter(control =>
		control.functionId.includes(`|function|${name}|`))
	if (decisions.length !== expectedCount) {
		fail(`expected ${expectedCount} sealed ${name} loop transfers, got ${decisions.length}`)
	}
}

for (const target of mainTargets) {
	if (!target.id
		|| (target.kind !== 'while' && target.kind !== 'do-while')
		|| target.proofId !== 'lexical-loop-control-v1'
		|| target.pipelineRevision !== 'ocaml-function-plans-v84') {
		fail(`loop target ${target.id} has incomplete kind, proof, or revision metadata`)
	}
}
for (const control of mainTransfers) {
	const target = targetById.get(control.targetId)
	const isBreak = control.kind === 'break'
	if (!target
		|| control.payload !== null
		|| (control.kind !== 'break' && control.kind !== 'continue')
		|| control.effect !== (isBreak ? 'exit-loop' : 'next-loop-iteration')
		|| control.mechanism !== (isBreak ? 'runtime-break-signal' : 'runtime-continue-signal')
		|| control.runtimeCapabilityId !== (isBreak ? 'hxhx-runtime:loop-break-signal-v1' : 'hxhx-runtime:loop-continue-signal-v1')
		|| control.runtimeTags.length !== 0
		|| control.runtimeTagPolicy !== 'no-runtime-tags'
		|| control.proofId !== 'lexical-loop-control-v1'
		|| control.functionId !== target.functionId
		|| control.bodyRevision !== target.bodyRevision
		|| control.pipelineRevision !== target.pipelineRevision) {
		fail(`loop transfer ${control.id} does not match its sealed lexical target`)
	}
}

const tryStart = source.indexOf('let throughTry =')
const tryEnd = source.indexOf('\nlet voidLoop =', tryStart)
const tryBody = source.slice(tryStart, tryEnd)
	if (tryStart < 0
		|| tryEnd < 0
		|| !/HxRuntime\.Hx_break -> raise \(HxRuntime\.Hx_break\)/.test(tryBody)
		|| !/HxRuntime\.Hx_continue -> raise \(HxRuntime\.Hx_continue\)/.test(tryBody)) {
	fail('a source catch can intercept a private loop-control signal')
}

for (const name of ['nestedLoops', 'doWhileContinue', 'throughTry', 'voidLoop', 'floatLoop', 'nestedFunction']) {
	const start = source.indexOf(`let ${name} =`)
	const next = source.indexOf('\nlet ', start + 1)
	const body = source.slice(start, next)
	if (start < 0 || next < 0 || !body.includes('HxRuntime.Hx_break') || !body.includes('HxRuntime.Hx_continue')) {
		fail(`${name} did not emit mechanically matched private loop-control boundaries`)
	}
}
NODE

cp "$REPORT_FILE" "$REPORT_COPY"
cp "$MANIFEST_FILE" "$MANIFEST_COPY"
haxe build.hxml
if ! cmp -s "$REPORT_COPY" "$REPORT_FILE"; then
	echo "The exact same typed program produced a different loop-control report" >&2
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
if (report.schemaVersion !== 45
	|| report.summary.valid !== true
	|| report.summary.controlCount !== report.lowering.controls.length
	|| report.summary.controlTargetCount !== report.lowering.controlTargets.length
	|| report.lowering.scope !== 'typed-place-anonymous-object-call-and-function-loop-throw-catch-control-families') {
	throw new Error('public inspection did not expose the validated function/loop control inventory')
}
NODE

node - "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const transfer = report.controls.find(control =>
	control.targetKind === 'loop' && control.functionId.includes('Main|'))
if (!transfer)
	throw new Error('missing Main loop transfer to corrupt')
transfer.targetId = 'control-target:loop:missing'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision "$REPORT_FILE"

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$TAMPER_INSPECTION" 2>&1; then
	echo "Public inspection accepted a control transfer whose sealed loop target was missing" >&2
	exit 1
fi
if ! grep -q "missing loop target" "$TAMPER_INSPECTION"; then
	echo "Public inspection rejected the corrupt loop target without the expected actionable reason" >&2
	cat "$TAMPER_INSPECTION" >&2
	exit 1
fi
cp "$REPORT_COPY" "$REPORT_FILE"
cp "$MANIFEST_COPY" "$MANIFEST_FILE"

echo "REFLAXE_OCAML_LOOP_CONTROL_FIXTURE:PASS targets=7 transfers=12"
