#!/usr/bin/env bash
set -euo pipefail

main_source="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$main_source" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated function-value call source or lowering report" >&2
	exit 1
fi

if [ "$(grep -Ec 'let __call_callee_[0-9]+ = .* in let __call_arg_0_[0-9]+ = .* in __call_callee_[0-9]+ __call_arg_0_[0-9]+' "$main_source")" -lt 4 ]; then
	echo "Every admitted function-value call must bind its callee before its argument" >&2
	exit 1
fi
if grep -Eq 'Obj\.magic.*__call_callee_|__call_callee_.*Obj\.magic' "$main_source"; then
	echo "The exact Int function-value call must not introduce Obj.magic" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (report.schemaVersion !== 63 || report.callModel !== 'typed-ocaml-directional-call-boundary-v20') {
	throw new Error('expected the function-value-aware typed-call report schema')
}
const calls = (report.calls ?? []).filter(call => call.kind === 'typed-function-value')
if (calls.length !== 4) {
	throw new Error(`expected four typed function-value calls, got ${calls.length}`)
}
for (const call of calls) {
	if (call.arguments?.length !== 1
		|| call.arguments[0]?.inputSemanticTypeId !== 'Int'
		|| call.arguments[0]?.outputSemanticTypeId !== 'Int'
		|| call.resultKind !== 'value'
		|| call.result?.inputSemanticTypeId !== 'Int'
		|| call.result?.outputSemanticTypeId !== 'Int'
		|| call.sourceModuleId !== ''
		|| call.sourceTypeName !== ''
		|| call.sourceFieldName !== ''
		|| call.proofId !== 'typed-function-value-signature-matrix-v1:(Int)->Int') {
		throw new Error(`call ${call.id} did not preserve the exact Int -> Int contract`)
	}
	const kinds = (call.evaluationSchedule ?? []).map(step => step.kind)
	if (kinds.join(',') !== 'materialize-callee,materialize-argument,invoke-callee') {
		throw new Error(`call ${call.id} has an invalid evaluation schedule: ${kinds.join(',')}`)
	}
}
NODE

first_report="$(mktemp)"
inspection_report="$(mktemp)"
trap 'rm -f "$first_report" "$inspection_report"' EXIT
cp "$report_file" "$first_report"
haxe build.hxml -D ocaml_build=native
if ! cmp -s "$first_report" "$report_file"; then
	echo "The function-value call report changed across identical compiler runs" >&2
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
	throw new Error('reflaxe.ocaml inspection rejected the sealed function-value call report')
}
const calls = report.lowering?.calls?.filter(call => call.kind === 'typed-function-value') ?? []
if (calls.length !== 4
	|| calls.some(call => call.evaluationSchedule?.map(step => step.kind).join(',') !==
		'materialize-callee,materialize-argument,invoke-callee')) {
	throw new Error('reflaxe.ocaml inspection did not preserve the function-value call schedules')
}
NODE

echo "EXACT_INT_FUNCTION_VALUE_CALL_PLAN:PASS"
