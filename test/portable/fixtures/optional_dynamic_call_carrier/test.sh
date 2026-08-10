#!/usr/bin/env bash
set -euo pipefail

# The installed Haxe 4.3.7 interpreter supplies expected behavior without
# executing the OCaml target implementation under test.
haxe -cp src --run Main | diff -u expected.stdout -

node - out/Main.ml out/ocaml_lowering_report.json out/ocaml_runtime_requirement_report.json <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const lowering = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const runtime = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'))

const optionalDynamicCalls = (lowering.calls ?? []).filter(call =>
	(call.arguments ?? []).some(argument =>
		argument.parameterOptional === true
		&& argument.outputSemanticTypeId === 'Dynamic'))
if (optionalDynamicCalls.length !== 7) {
	throw new Error(`expected seven sealed optional Dynamic calls, got ${optionalDynamicCalls.length}`)
}
const omitted = optionalDynamicCalls.find(call =>
	(call.arguments ?? []).some(argument => argument.conversion === 'materialize-omitted-dynamic'))
if (omitted?.evaluationSchedule?.map(step => step.kind).join(',') !==
	'materialize-omitted-argument,invoke-callee') {
	throw new Error('the omitted Dynamic call did not materialize its null carrier before invocation')
}
const conversions = optionalDynamicCalls.flatMap(call => call.arguments ?? [])
	.filter(argument => argument.parameterOptional === true)
	.map(argument => argument.conversion)
if (!conversions.includes('materialize-explicit-null-dynamic')
	|| !conversions.includes('box-exact-bool-to-dynamic')
	|| conversions.filter(conversion => conversion === 'box-concrete-to-dynamic').length !== 4) {
	throw new Error(`the optional Dynamic matrix is incomplete: ${conversions.join(',')}`)
}
if (!optionalDynamicCalls.some(call => call.kind === 'typed-function-value')) {
	throw new Error('the optional Dynamic callback did not use the same sealed call contract')
}
if (!source.includes('fun (value : Obj.t)') || (source.match(/HxRuntime\.box_bool/g) ?? []).length !== 1) {
	throw new Error('the generated callable must use one Obj.t carrier and one checked Boolean box')
}
const boolRequirements = (runtime.requirements ?? []).filter(requirement =>
	requirement.semanticCapability === 'haxe-call-bool-carrier')
if (boolRequirements.length !== 1) {
	throw new Error(`expected one Boolean carrier requirement, got ${boolRequirements.length}`)
}
NODE

echo "OPTIONAL_DYNAMIC_CALL_CARRIER:PASS"
