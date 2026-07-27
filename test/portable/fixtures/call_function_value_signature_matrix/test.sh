#!/usr/bin/env bash
set -euo pipefail

main_source="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$main_source" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated function-value signature-matrix source or lowering report" >&2
	exit 1
fi

node - "$main_source" "$report_file" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 23 || report.callModel !== 'typed-ocaml-directional-call-boundary-v14') {
	fail('unexpected lowering report or call-model version')
}

const proofPrefix = 'typed-function-value-signature-matrix-v1:'
const calls = (report.calls ?? []).filter(call =>
	call.kind === 'typed-function-value' && call.proofId?.startsWith(proofPrefix))
if (calls.length !== 11) {
	fail(`expected eleven signature-matrix calls, got ${calls.length}`)
}
const expectedProofCounts = new Map([
	['typed-function-value-signature-matrix-v1:(Bool,Int)->String', 2],
	['typed-function-value-signature-matrix-v1:()->Bool', 2],
	['typed-function-value-signature-matrix-v1:(Null<Int>)->Null<Int>', 1],
	['typed-function-value-signature-matrix-v1:(?Null<Int>)->Int', 2],
	['typed-function-value-signature-matrix-v1:(?Null<Bool>)->Bool', 2],
	['typed-function-value-signature-matrix-v1:(String)->Void', 2]
])
for (const [proofId, expected] of expectedProofCounts) {
	const actual = calls.filter(call => call.proofId === proofId).length
	if (actual !== expected) {
		fail(`expected ${expected} calls for ${proofId}, got ${actual}`)
	}
}

let omittedInt = 0
let omittedBool = 0
let effectOnly = 0
for (const call of calls) {
	if (call.sourceModuleId !== '' || call.sourceTypeName !== '' || call.sourceFieldName !== '') {
		fail(`computed call ${call.id} incorrectly owns declaration identity`)
	}
	if (call.resultKind === 'effect-only-void') {
		effectOnly += 1
		if (call.result !== null) {
			fail(`effect-only call ${call.id} owns a result carrier`)
		}
	} else if (call.resultKind !== 'value' || call.result == null || call.result.conversion !== 'identity') {
		fail(`value call ${call.id} lost its exact result carrier`)
	}
	const expectedKinds = [
		'materialize-callee',
		...call.arguments.map(argument => {
			if (argument.conversion === 'materialize-omitted-nullable-int') {
				omittedInt += 1
				return 'materialize-omitted-argument'
			}
			if (argument.conversion === 'materialize-omitted-nullable-bool') {
				omittedBool += 1
				return 'materialize-omitted-argument'
			}
			return 'materialize-argument'
		}),
		'invoke-callee'
	]
	const schedule = call.evaluationSchedule ?? []
	if (schedule.map(step => step.kind).join(',') !== expectedKinds.join(',')) {
		fail(`computed call ${call.id} has the wrong schedule`)
	}
	for (const step of schedule) {
		if (step.kind === 'materialize-omitted-argument' && step.sourceArgumentIndex !== null) {
			fail(`computed call ${call.id} evaluates source for an omission`)
		}
	}
}
if (omittedInt !== 1 || omittedBool !== 1 || effectOnly !== 2) {
	fail(`unexpected matrix partition: omittedInt=${omittedInt}, omittedBool=${omittedBool}, effectOnly=${effectOnly}`)
}

const callLines = source.split('\n').filter(line => line.includes('let __call_callee_'))
if (callLines.length !== 11) {
	fail(`expected eleven syntax-level callee bindings, got ${callLines.length}`)
}
for (const line of callLines) {
	const callee = line.match(/let (__call_callee_[0-9]+) =/)?.[1]
	if (callee == null || !line.includes(` in ${callee} `)) {
		fail(`planned call did not bind then invoke its computed callee: ${line}`)
	}
}
const factoryLines = callLines.filter(line =>
	/= make(?:Mixed|Probe|OptionalInt|OptionalBool|Effect) \(\)/.test(line))
if (factoryLines.length !== 5) {
	fail(`expected five factory-produced callee bindings, got ${factoryLines.length}`)
}
NODE

first_report="$(mktemp)"
inspection_report="$(mktemp)"
invalid_inspection_log="$(mktemp)"
invalid_output="out-invalid-function-value-matrix-$$"
trap 'rm -f "$first_report" "$inspection_report" "$invalid_inspection_log"; rm -rf "$invalid_output"' EXIT
cp "$report_file" "$first_report"
haxe build.hxml -D ocaml_build=native
if ! cmp -s "$first_report" "$report_file"; then
	echo "The function-value signature-matrix report changed across identical compiler runs" >&2
	exit 1
fi

repo_root="$(cd ../../../.. && pwd)"
fixture_root="$PWD"
(
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output out --require-lowering --json
) >"$inspection_report"
node - "$inspection_report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (!report.summary?.valid) {
	throw new Error('reflaxe.ocaml inspection rejected the sealed function-value matrix report')
}
const calls = report.lowering?.calls?.filter(call =>
	call.kind === 'typed-function-value'
	&& call.proofId?.startsWith('typed-function-value-signature-matrix-v1:')) ?? []
if (calls.length !== 11) {
	throw new Error(`reflaxe.ocaml inspection retained ${calls.length} matrix calls instead of eleven`)
}
NODE

cp -R out "$invalid_output"
node - "$invalid_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const selected = report.calls?.find(call =>
	call.kind === 'typed-function-value'
	&& call.proofId === 'typed-function-value-signature-matrix-v1:(Bool,Int)->String')
if (selected == null) {
	throw new Error('missing mixed callback call to corrupt')
}
selected.proofId = 'typed-function-value-signature-matrix-v1:(Int,Int)->String'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
if (
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output "$invalid_output" --require-lowering --json
) >"$invalid_inspection_log" 2>&1; then
	echo "The external inspector accepted a function-value proof bound to the wrong signature" >&2
	exit 1
fi
if ! grep -Fq "wrong canonical function-value signature" "$invalid_inspection_log"; then
	echo "The external inspector rejected the malformed signature proof for an unexpected reason" >&2
	cat "$invalid_inspection_log" >&2
	exit 1
fi

echo "FUNCTION_VALUE_SIGNATURE_MATRIX:PASS"
