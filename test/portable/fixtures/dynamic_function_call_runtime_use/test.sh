#!/usr/bin/env bash
set -euo pipefail

# Stock Haxe 4.3.7 supplies the independent source-language behavior oracle.
haxe -cp src --run Main | diff -u expected.stdout -

node - out/Main.ml out/ocaml_lowering_report.json out/ocaml_runtime_requirement_report.json <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const lowering = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const runtime = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'))

if (lowering.schemaVersion !== 83
	|| lowering.callModel !== 'typed-ocaml-directional-call-boundary-v29') {
	throw new Error('unexpected lowering-report contract for sealed Dynamic calls')
}
const calls = (lowering.calls ?? []).filter(call => call.kind === 'dynamic-function-value')
if (calls.length !== 5) {
	throw new Error(`expected five sealed Dynamic calls, got ${calls.length}`)
}
const argumentCounts = calls.map(call => call.dynamicFunctionTarget?.argumentSemanticTypeIds?.length).sort()
if (argumentCounts.join(',') !== '0,1,1,2,2') {
	throw new Error(`unexpected Dynamic-call argument counts: ${argumentCounts.join(',')}`)
}
for (const call of calls) {
	const count = call.dynamicFunctionTarget.argumentSemanticTypeIds.length
	const expectedSchedule = [
		'materialize-callee',
		...Array(count).fill('materialize-argument'),
		'invoke-callee'
	]
	if (call.evaluationSchedule?.map(step => step.kind).join(',') !== expectedSchedule.join(',')) {
		throw new Error(`Dynamic call ${call.id} does not evaluate its callee before its arguments`)
	}
}

const requirements = (runtime.requirements ?? []).filter(requirement =>
	requirement.semanticCapability === 'haxe-dynamic-function-call')
if (requirements.length !== 21 || new Set(requirements.map(requirement => requirement.id)).size !== 21) {
	throw new Error(`expected twenty-one distinct Dynamic-call requirements, got ${requirements.length}`)
}
const rootCounts = new Map()
for (const requirement of requirements) {
	if (requirement.implementationFeature !== 'haxe-dynamic-function-call-v1'
		|| requirement.rootModules?.length !== 1) {
		throw new Error(`invalid Dynamic-call runtime requirement: ${JSON.stringify(requirement)}`)
	}
	const root = requirement.rootModules[0]
	rootCounts.set(root, (rootCounts.get(root) ?? 0) + 1)
}
if (rootCounts.get('HxArray') !== 11 || rootCounts.get('HxReflect') !== 5 || rootCounts.get('HxRuntime') !== 5) {
	throw new Error(`unexpected Dynamic-call runtime roots: ${JSON.stringify(Object.fromEntries(rootCounts))}`)
}
if ((source.match(/let __dynamic_callee_/g) ?? []).length !== 5
	|| source.includes('let __dyn_args_')) {
	throw new Error('generated OCaml did not use the sealed callee-first Dynamic-call path')
}
NODE

repo_root="$(cd ../../../.. && pwd)"
fixture_root="$PWD"
inspection_report="$(mktemp)"
invalid_inspection_log="$(mktemp)"
invalid_output="out-invalid-dynamic-call-$$"
trap 'rm -f "$inspection_report" "$invalid_inspection_log"; rm -rf "$invalid_output"' EXIT
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
const calls = report.lowering?.calls?.filter(call => call.kind === 'dynamic-function-value') ?? []
if (!report.summary?.valid || calls.length !== 5) {
	throw new Error('independent inspection rejected the five sealed Dynamic calls')
}
NODE

cp -R out "$invalid_output"
node - "$invalid_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const call = report.calls?.find(call => call.kind === 'dynamic-function-value')
if (call == null) {
	throw new Error('missing Dynamic call to corrupt')
}
call.dynamicFunctionTarget.calleeCarrierTypeId = 'string'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
if (
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output "$invalid_output" --require-lowering --json
) >"$invalid_inspection_log" 2>&1; then
	echo "The inspector accepted a Dynamic call with the wrong callee carrier" >&2
	exit 1
fi
if ! grep -Fq "incomplete or conflicting target facts" "$invalid_inspection_log"; then
	echo "The inspector rejected the malformed Dynamic call for an unexpected reason" >&2
	cat "$invalid_inspection_log" >&2
	exit 1
fi

echo "DYNAMIC_FUNCTION_CALL_RUNTIME_USE:PASS"
