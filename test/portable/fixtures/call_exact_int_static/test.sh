#!/usr/bin/env bash
set -euo pipefail

arithmetic_source="out/Arithmetic.ml"
main_source="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$arithmetic_source" ] || [ ! -f "$main_source" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated call fixture source or lowering report" >&2
	exit 1
fi

if ! grep -q '^let increment = fun (value : int) ->' "$arithmetic_source"; then
	echo "The exact Int callable boundary must annotate its OCaml parameter as int" >&2
	exit 1
fi
if ! grep -q 'Arithmetic.increment (sourceValue ())' "$main_source"; then
	echo "The admitted direct static call must use the sealed target and source argument" >&2
	exit 1
fi
if grep -q 'Obj.magic.*Arithmetic.increment\\|Arithmetic.increment.*Obj.magic' "$main_source"; then
	echo "The exact Int call boundary must not introduce Obj.magic" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const call = report.calls?.find(item => item.sourceTypeName === 'Arithmetic' && item.sourceFieldName === 'increment')
const boundary = report.callableBoundaries?.find(item => item.calleeId === call?.calleeId)
if (!call
	|| call.kind !== 'direct-static-haxe-method'
	|| call.arguments?.length !== 1
	|| call.arguments[0].semanticTypeId !== 'Int'
	|| call.arguments[0].carrierTypeId !== 'int'
	|| call.arguments[0].conversion !== 'identity'
	|| call.result?.semanticTypeId !== 'Int'
	|| call.result?.carrierTypeId !== 'int'
	|| call.evaluationSchedule?.join(',') !== 'evaluate-argument:0,invoke-callee') {
	throw new Error('the lowering report did not preserve the exact one-argument Int call decision')
}
if (!boundary
	|| boundary.arguments?.length !== 1
	|| boundary.arguments[0].representationId !== call.arguments[0].representationId
	|| boundary.result?.representationId !== call.result.representationId) {
	throw new Error('the call does not match an independently sealed callable definition')
}
for (const excluded of ['add', 'identity']) {
	if (report.calls.some(item => item.sourceFieldName === excluded)
		|| report.callableBoundaries.some(item => item.sourceFieldName === excluded)) {
		throw new Error(`non-admitted static method ${excluded} entered the first exact call family`)
	}
}
if (report.calls.some(item => item.sourceTypeName === 'Counter')
	|| report.callableBoundaries.some(item => item.sourceTypeName === 'Counter')) {
	throw new Error('an instance method entered the first direct-static call family')
}
NODE

echo "EXACT_INT_STATIC_CALL_PLAN:PASS"
