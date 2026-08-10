#!/usr/bin/env bash
set -euo pipefail

# The installed Haxe 4.3.7 interpreter is the independent behavior oracle.
# It does not execute the OCaml target implementation under test.
haxe -cp src --run Main | diff -u expected.stdout -

node - out/Main.ml out/ocaml_lowering_report.json out/ocaml_runtime_requirement_report.json <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const lowering = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const runtime = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'))

const boolCalls = (lowering.calls ?? []).filter(call =>
	(call.arguments ?? []).some(argument => argument.conversion === 'box-exact-bool-to-dynamic'))
if (boolCalls.length !== 3) {
	throw new Error(`expected three sealed Bool-to-Dynamic calls, got ${boolCalls.length}`)
}
const kinds = boolCalls.map(call => call.kind).sort()
if (kinds.join(',') !== 'direct-static-haxe-method,direct-static-haxe-method,typed-function-value') {
	throw new Error(`unexpected Bool-to-Dynamic call kinds: ${kinds.join(',')}`)
}
const functionCall = boolCalls.find(call => call.kind === 'typed-function-value')
if (functionCall.evaluationSchedule?.map(step => step.kind).join(',') !==
	'materialize-callee,materialize-argument,invoke-callee') {
	throw new Error('the function-value call did not preserve callee-before-argument evaluation')
}
const optionalCall = boolCalls.find(call => call.sourceFieldName === 'describeWithLabel')
if (optionalCall?.evaluationSchedule?.map(step => step.kind).join(',') !==
	'materialize-argument,materialize-omitted-argument,invoke-callee') {
	throw new Error('the optional call did not materialize the Bool before its omitted trailing argument')
}

const requirements = (runtime.requirements ?? []).filter(requirement =>
	requirement.semanticCapability === 'haxe-call-bool-carrier')
if (requirements.length !== 3
	|| new Set(requirements.map(requirement => requirement.id)).size !== 3
	|| requirements.some(requirement => requirement.rootModules?.join(',') !== 'HxRuntime'
		|| requirement.implementationFeature !== 'haxe-boolean-carrier-v1')) {
	throw new Error('each Bool-to-Dynamic call must own one distinct HxRuntime requirement')
}
if ((source.match(/HxRuntime\.box_bool/g) ?? []).length !== 3) {
	throw new Error('generated OCaml must contain exactly three Bool boxes')
}
NODE

echo "CALL_BOOL_DYNAMIC_RUNTIME_USE:PASS"
