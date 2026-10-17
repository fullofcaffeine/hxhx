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
const assert = require('node:assert/strict')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 94 || report.callModel !== 'typed-ocaml-directional-call-boundary-v34') {
	fail('unexpected lowering report or call-model version')
}

const proofPrefix = 'typed-function-value-signature-matrix-v1:'
const calls = (report.calls ?? []).filter(call => call.kind === 'typed-function-value')
if (calls.length !== 11) {
	fail(`expected eleven signature-matrix calls, got ${calls.length}`)
}
// Signatures remain exact when local callbacks acquire a separate identity.
// Derive the inventory from argument/result types, then check the proof and
// storage evidence for each authored case below.
const signature = call => `(${call.arguments.map(argument =>
	`${argument.parameterOptional ? '?' : ''}${argument.outputSemanticTypeId}`).join(',')})->${
	call.resultKind === 'effect-only-void' ? 'Void' : call.result?.outputSemanticTypeId}`
const expectedSignatureCounts = new Map([
	['(Bool,Int)->String', 2],
	['()->Bool', 2],
	['(Null<Int>)->Null<Int>', 1],
	['(?Null<Int>)->Int', 2],
	['(?Null<Bool>)->Bool', 2],
	['(String)->Void', 2]
])
for (const [type, expected] of expectedSignatureCounts) {
	const actual = calls.filter(call => signature(call) === type).length
	if (actual !== expected) {
		fail(`expected ${expected} calls for ${type}, got ${actual}`)
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
const viewCases = ['mixedLocalCase', 'zeroLocalCase', 'nullableIntCase', 'effectLocalCase']
const rawCases = ['mixedFactoryCase', 'zeroFactoryCase', 'optionalIntOmittedCase', 'optionalIntFactorySuppliedCase',
	'optionalBoolOmittedCase', 'optionalBoolFactorySuppliedCase', 'effectFactoryCase']
const expectedSignatures = new Map([
	['mixedLocalCase', '(Bool,Int)->String'], ['mixedFactoryCase', '(Bool,Int)->String'],
	['zeroLocalCase', '()->Bool'], ['zeroFactoryCase', '()->Bool'],
	['nullableIntCase', '(Null<Int>)->Null<Int>'],
	['optionalIntOmittedCase', '(?Null<Int>)->Int'], ['optionalIntFactorySuppliedCase', '(?Null<Int>)->Int'],
	['optionalBoolOmittedCase', '(?Null<Bool>)->Bool'], ['optionalBoolFactorySuppliedCase', '(?Null<Bool>)->Bool'],
	['effectLocalCase', '(String)->Void'], ['effectFactoryCase', '(String)->Void']
])
for (const name of [...viewCases, ...rawCases]) {
	const body = source.match(new RegExp(`\\nlet ${name} = ([\\s\\S]*?)(?=\\nlet |$)`))?.[1]
	const callee = body?.match(/let (__call_callee_[0-9]+) =/)?.[1]
	const view = viewCases.includes(name)
	const invocation = view ? `Stdlib.fst ${callee}` : callee
	if (callee == null || !body.includes(` in ${invocation} `))
		fail(`${name} did not bind then invoke its ${view ? 'view' : 'raw'} computed callee`)
	const entries = report.callableViews.entries.filter(entry => entry.decision.binding.functionId.includes(`|function|${name}|`))
	if (entries.length !== (view ? 1 : 0))
		fail(`${name} has unexpected callback storage evidence`)
	const selected = calls.filter(call => call.functionId.includes(`|function|${name}|`))
	assert.equal(selected.length, 1, `${name} must retain exactly one computed invocation`)
	const call = selected[0]
	assert.equal(signature(call), expectedSignatures.get(name), `${name} lost its exact signature`)
	assert.equal(call.proofId, view ? 'typed-callable-view-invocation-v1' : proofPrefix + signature(call))
	if (view) {
		const invocation = call.callbackInvocation
		const storage = entries[0].decision
		assert.equal(invocation?.input.kind, 'existing-view')
		assert.deepEqual(invocation.input.reference, storage.output)
		assert.deepEqual(invocation.layout, {
			shape: storage.adapter.output,
			revision: storage.adapter.outputRevision,
			semanticTypeId: storage.output.semanticTypeId,
			carrierTypeId: `callable-view<${storage.output.semanticTypeId}>`
		})
		assert.equal(storage.output.semanticTypeId, expectedSignatures.get(name))
		for (const key of ['functionId', 'programRevision', 'bodyRevision', 'pipelineRevision'])
			assert.equal(storage.binding[key], call[key], `${name} lost its containing body`)
		assert.deepEqual(invocation.source, {
			file: call.source.file, min: call.source.min, max: call.source.min + 'callback'.length
		})
	} else {
		assert.equal(call.callbackInvocation, null, `${name} must retain its raw function carrier`)
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
const calls = report.lowering?.calls?.filter(call => call.kind === 'typed-function-value') ?? []
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
