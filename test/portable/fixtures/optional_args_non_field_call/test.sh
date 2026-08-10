#!/usr/bin/env bash
set -euo pipefail

main_source="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$main_source" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated optional function-value source or lowering report" >&2
	exit 1
fi

node - "$main_source" "$report_file" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 79 || report.callModel !== 'typed-ocaml-directional-call-boundary-v28') {
	fail('expected the optional-function-value-aware typed-call report schema')
}
const calls = (report.calls ?? []).filter(call =>
	call.kind === 'typed-function-value'
	&& (call.proofId === 'typed-function-value-signature-matrix-v1:(?String)->String'
		|| call.proofId === 'typed-function-value-signature-matrix-v1:(String,?String)->String'))
if (calls.length !== 17) {
	fail(`expected seventeen optional String function-value calls, got ${calls.length}`)
}

let oneParameterCalls = 0
let twoParameterCalls = 0
let omittedCalls = 0
let explicitNullCalls = 0
for (const call of calls) {
	if (call.sourceModuleId !== '' || call.sourceTypeName !== '' || call.sourceFieldName !== '') {
		fail(`computed call ${call.id} incorrectly owns declaration identity`)
	}
	if (call.resultKind !== 'value'
		|| call.result?.inputSemanticTypeId !== 'String'
		|| call.result?.outputSemanticTypeId !== 'String'
		|| call.result?.inputCarrierTypeId !== 'string'
		|| call.result?.outputCarrierTypeId !== 'string'
		|| call.result?.conversion !== 'identity') {
		fail(`computed call ${call.id} does not preserve its exact String result`)
	}
	if (call.arguments?.length === 1) {
		oneParameterCalls += 1
	} else if (call.arguments?.length === 2) {
		twoParameterCalls += 1
		if (call.arguments[0].parameterOptional || call.arguments[0].conversion !== 'identity') {
			fail(`computed call ${call.id} changed its required String parameter`)
		}
	} else {
		fail(`computed call ${call.id} has an unsupported arity`)
	}
	const trailing = call.arguments[call.arguments.length - 1]
	if (!trailing.parameterOptional
		|| trailing.inputSemanticTypeId !== 'String'
		|| trailing.outputSemanticTypeId !== 'String'
		|| trailing.inputCarrierTypeId !== 'string'
		|| trailing.outputCarrierTypeId !== 'string') {
		fail(`computed call ${call.id} lost its trailing optional String boundary`)
	}

	const omitted = trailing.conversion === 'materialize-omitted-string'
	if (omitted) {
		omittedCalls += 1
	} else if (trailing.conversion === 'materialize-explicit-null-string') {
		explicitNullCalls += 1
	} else if (trailing.conversion !== 'identity'
		&& trailing.conversion !== 'materialize-explicit-null-string') {
		fail(`computed call ${call.id} selected unsupported conversion ${trailing.conversion}`)
	}
	const expectedKinds = [
		'materialize-callee',
		...call.arguments.map(argument =>
			argument.conversion === 'materialize-omitted-string'
				? 'materialize-omitted-argument'
				: 'materialize-argument'),
		'invoke-callee'
	]
	const schedule = call.evaluationSchedule ?? []
	const actualKinds = schedule.map(step => step.kind)
	if (actualKinds.join(',') !== expectedKinds.join(',')) {
		fail(`computed call ${call.id} has schedule ${actualKinds.join(',')}`)
	}
	for (const step of schedule) {
		if (step.kind === 'materialize-omitted-argument' && step.sourceArgumentIndex !== null) {
			fail(`computed call ${call.id} evaluates a source expression for omission`)
		}
	}
}
if (oneParameterCalls !== 8 || twoParameterCalls !== 9 || omittedCalls !== 5 || explicitNullCalls !== 4) {
	fail(`unexpected optional call partition: one=${oneParameterCalls}, two=${twoParameterCalls}, omitted=${omittedCalls}, explicitNull=${explicitNullCalls}`)
}

const callLines = source.split('\n').filter(line => line.includes('let __call_callee_'))
if (callLines.length !== 17) {
	fail(`expected seventeen syntax-level callee bindings, got ${callLines.length}`)
}
for (const line of callLines) {
	const callee = line.match(/let (__call_callee_[0-9]+) =/)?.[1]
	if (callee == null || !line.includes(` in let __call_arg_`) || !line.includes(` in ${callee} `)) {
		fail(`planned call did not bind then invoke its computed callee: ${line}`)
	}
	if (line.includes('Obj.magic') || line.includes('HxRuntime.hx_null') || line.includes('""')) {
		fail(`planned optional String call used an unsealed fallback carrier: ${line}`)
	}
}
if (callLines.filter(line => line.includes('HxString.hx_null_string')).length !== 9) {
	fail('exactly the omitted and literal-null calls must materialize the selected String null sentinel')
}
const callProducedLines = callLines.filter(line =>
	/= (?:makeGreeter|makeOnly|failingGreeter) \(\)/.test(line))
if (callProducedLines.length !== 9) {
	fail(`expected nine call-produced callee bindings, got ${callProducedLines.length}`)
}
NODE

first_report="$(mktemp)"
inspection_report="$(mktemp)"
invalid_inspection_log="$(mktemp)"
invalid_output="out-invalid-optional-function-value-$$"
trap 'rm -f "$first_report" "$inspection_report" "$invalid_inspection_log"; rm -rf "$invalid_output"' EXIT
cp "$report_file" "$first_report"
haxe build.hxml -D ocaml_build=native
if ! cmp -s "$first_report" "$report_file"; then
	echo "The optional function-value call report changed across identical compiler runs" >&2
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
	throw new Error('reflaxe.ocaml inspection rejected the sealed optional function-value report')
}
const calls = report.lowering?.calls?.filter(call =>
	call.kind === 'typed-function-value'
	&& (call.proofId === 'typed-function-value-signature-matrix-v1:(?String)->String'
		|| call.proofId === 'typed-function-value-signature-matrix-v1:(String,?String)->String')) ?? []
if (calls.length !== 17
	|| calls.filter(call => call.arguments?.some(argument =>
		argument.conversion === 'materialize-omitted-string')).length !== 5
	|| calls.filter(call => call.arguments?.some(argument =>
		argument.conversion === 'materialize-explicit-null-string')).length !== 4) {
	throw new Error('reflaxe.ocaml inspection did not preserve the optional function-value calls')
}
NODE

cp -R out "$invalid_output"
node - "$invalid_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const selected = report.calls?.find(call =>
	call.kind === 'typed-function-value'
	&& (call.proofId === 'typed-function-value-signature-matrix-v1:(?String)->String'
		|| call.proofId === 'typed-function-value-signature-matrix-v1:(String,?String)->String')
	&& call.arguments?.some(argument =>
		argument.conversion === 'materialize-omitted-string'))
if (selected == null) {
	throw new Error('missing optional function-value call to corrupt')
}
selected.arguments[selected.arguments.length - 1].parameterOptional = false
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
if (
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output "$invalid_output" --require-lowering --json
) >"$invalid_inspection_log" 2>&1; then
	echo "The external inspector accepted an optional function value whose trailing parameter was no longer optional" >&2
	exit 1
fi
if ! grep -Fq "invalid omitted optional String materialization" "$invalid_inspection_log"; then
	echo "The external inspector rejected the malformed report for an unexpected reason" >&2
	cat "$invalid_inspection_log" >&2
	exit 1
fi

echo "OPTIONAL_STRING_FUNCTION_VALUE_CALL_PLAN:PASS"
