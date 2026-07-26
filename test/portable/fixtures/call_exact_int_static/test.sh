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
if ! grep -Eq 'let __call_arg_0_[0-9]+ = sourceValue \(\) in Arithmetic\.increment __call_arg_0_[0-9]+' "$main_source"; then
	echo "The one-argument direct static call must materialize its sealed source argument" >&2
	exit 1
fi
if ! grep -q '^let add = fun (left : int) (right : int) ->' "$arithmetic_source"; then
	echo "The exact two-Int callable boundary must annotate both OCaml parameters as int" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = firstValue \(\) in let __call_arg_1_[0-9]+ = secondValue \(\) in Arithmetic\.add __call_arg_0_[0-9]+ __call_arg_1_[0-9]+' "$main_source"; then
	echo "The two-argument call must materialize first, then second, before invoking the sealed target" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = throwingFirst \(\) in let __call_arg_1_[0-9]+ = shouldNotRun \(\) in Arithmetic\.add __call_arg_0_[0-9]+ __call_arg_1_[0-9]+' "$main_source"; then
	echo "The exceptional two-argument call must preserve the same sealed order" >&2
	exit 1
fi
if grep -Eq 'Arithmetic\.add \(firstValue \(\)\) \(secondValue \(\)\)' "$main_source"; then
	echo "The exact two-argument call must not rely on direct OCaml application order" >&2
	exit 1
fi
if grep -q 'Obj.magic.*Arithmetic.increment\\|Arithmetic.increment.*Obj.magic' "$main_source"; then
	echo "The exact Int call boundary must not introduce Obj.magic" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
function verifyCalls(fieldName, arity, proofId, expectedCount) {
	const calls = report.calls?.filter(item => item.sourceTypeName === 'Arithmetic' && item.sourceFieldName === fieldName) ?? []
	if (calls.length !== expectedCount) {
		throw new Error(`expected ${expectedCount} sealed ${fieldName} calls, found ${calls.length}`)
	}
	for (const call of calls) {
		const boundary = report.callableBoundaries?.find(item => item.calleeId === call?.calleeId)
		if (call.kind !== 'direct-static-haxe-method'
			|| call.arguments?.length !== arity
			|| call.arguments.some((argument, index) => argument.index !== index
				|| argument.semanticTypeId !== 'Int'
				|| argument.carrierTypeId !== 'int'
				|| argument.conversion !== 'identity')
			|| call.result?.semanticTypeId !== 'Int'
			|| call.result?.carrierTypeId !== 'int'
			|| call.proofId !== proofId
			|| call.evaluationSchedule?.length !== arity + 1) {
			throw new Error(`the lowering report did not preserve the exact ${arity}-argument Int call decision`)
		}
		for (let index = 0; index < arity; index++) {
			const step = call.evaluationSchedule[index]
			if (step?.kind !== 'materialize-argument' || step.argumentIndex !== index || typeof step.slotId !== 'string') {
				throw new Error(`call ${fieldName} did not materialize argument ${index} in source order`)
			}
		}
		const invocation = call.evaluationSchedule[arity]
		if (invocation?.kind !== 'invoke-callee' || invocation.argumentIndex !== null || invocation.slotId !== null) {
			throw new Error(`call ${fieldName} did not invoke only after all arguments`)
		}
		if (!boundary
			|| boundary.arguments?.length !== arity
			|| boundary.arguments.some((argument, index) => argument.representationId !== call.arguments[index].representationId)
			|| boundary.result?.representationId !== call.result.representationId) {
			throw new Error(`call ${fieldName} does not match an independently sealed callable definition`)
		}
	}
}
verifyCalls('increment', 1, 'direct-one-int-static-call-v1', 1)
verifyCalls('add', 2, 'direct-two-int-static-call-v1', 2)

for (const excluded of ['identity']) {
	if (report.calls.some(item => item.sourceFieldName === excluded)
		|| report.callableBoundaries.some(item => item.sourceFieldName === excluded)) {
		throw new Error(`non-admitted static method ${excluded} entered the exact direct-call family`)
	}
}
if (report.calls.some(item => item.sourceTypeName === 'Counter')
	|| report.callableBoundaries.some(item => item.sourceTypeName === 'Counter')) {
	throw new Error('an instance method entered the first direct-static call family')
}
NODE

oracle_output="$(mktemp)"
trap 'rm -f "$oracle_output"' EXIT
haxe -cp src --main Main --interp >"$oracle_output"
diff -u expected.stdout "$oracle_output"

echo "EXACT_INT_STATIC_CALL_PLAN:PASS"
