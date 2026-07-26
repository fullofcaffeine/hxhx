#!/usr/bin/env bash
set -euo pipefail

arithmetic_source="out/Arithmetic.ml"
nullable_source="out/NullableCalls.ml"
bool_source="out/BoolCalls.ml"
main_source="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$arithmetic_source" ] || [ ! -f "$nullable_source" ] || [ ! -f "$bool_source" ] || [ ! -f "$main_source" ] || [ ! -f "$report_file" ]; then
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
if ! grep -q '^let identity = fun (value : Obj.t) ->' "$nullable_source"; then
	echo "The exact Null<Int> callable boundary must annotate its OCaml parameter as Obj.t" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = existing in NullableCalls\.identity __call_arg_0_[0-9]+' "$main_source"; then
	echo "An existing Null<Int> carrier must cross the callable boundary without another box" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = Obj\.repr \(observedNullableInput \(\)\) in NullableCalls\.identity __call_arg_0_[0-9]+' "$main_source"; then
	echo "An exact Int source must be evaluated once and boxed once before the Null<Int> call" >&2
	exit 1
fi
if grep -Eq 'Obj\.repr \(Obj\.repr \(observedNullableInput \(\)\)\)' "$main_source"; then
	echo "The exact Int-to-Null<Int> call crossing must not box its argument twice" >&2
	exit 1
fi
if ! grep -q '^let negate = fun (value : bool) ->' "$bool_source"; then
	echo "The exact Bool callable boundary must annotate its OCaml parameter as bool" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = observedBoolInput \(\) in BoolCalls\.negate __call_arg_0_[0-9]+' "$main_source"; then
	echo "The exact Bool call must materialize its sealed source argument before invocation" >&2
	exit 1
fi
if grep -Eq 'Obj\.(magic|repr|obj) \(BoolCalls\.negate|BoolCalls\.negate \(Obj\.(magic|repr|obj)' "$main_source"; then
	echo "The exact Bool call boundary must remain a direct bool identity crossing" >&2
	exit 1
fi
if ! grep -q '^let identityNullable = fun (value : Obj.t) ->' "$bool_source"; then
	echo "The exact Null<Bool> callable boundary must annotate its OCaml parameter as Obj.t" >&2
	exit 1
fi
if [ "$(grep -Ec 'let __call_arg_0_[0-9]+ = existing(Null|False)Bool in BoolCalls\.identityNullable __call_arg_0_[0-9]+' "$main_source")" -ne 2 ]; then
	echo "Existing null and false Null<Bool> carriers must cross the callable boundary without another box" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = Obj\.repr \(observedBoolInput \(\)\) in BoolCalls\.identityNullable __call_arg_0_[0-9]+' "$main_source"; then
	echo "An exact Bool source must be evaluated once and boxed once before the Null<Bool> call" >&2
	exit 1
fi
if grep -Eq 'Obj\.repr \(Obj\.repr \(observedBoolInput \(\)\)\)' "$main_source"; then
	echo "The exact Bool-to-Null<Bool> call crossing must not box its argument twice" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (report.schemaVersion !== 16 || report.callModel !== 'typed-ocaml-directional-call-boundary-v3') {
	throw new Error('the lowering report does not expose the directional call-boundary schema')
}
function isIdentity(value, semanticTypeId, carrierTypeId) {
	return value?.inputSemanticTypeId === semanticTypeId
		&& value?.inputCarrierTypeId === carrierTypeId
		&& value?.inputRepresentationId === `representation:${semanticTypeId}:internal-value`
		&& value?.outputSemanticTypeId === semanticTypeId
		&& value?.outputCarrierTypeId === carrierTypeId
		&& value?.outputRepresentationId === `representation:${semanticTypeId}:internal-value`
		&& value?.conversion === 'identity'
		&& value?.proofId === 'identity-call-carrier-v1'
}
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
				|| !isIdentity(argument, 'Int', 'int'))
			|| !isIdentity(call.result, 'Int', 'int')
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
			|| boundary.arguments.some((argument, index) => argument.outputRepresentationId !== call.arguments[index].outputRepresentationId)
			|| boundary.result?.inputRepresentationId !== call.result.inputRepresentationId) {
			throw new Error(`call ${fieldName} does not match an independently sealed callable definition`)
		}
	}
}
verifyCalls('increment', 1, 'direct-one-int-static-call-v1', 1)
verifyCalls('add', 2, 'direct-two-int-static-call-v1', 2)

const nullableCalls = report.calls?.filter(item => item.sourceTypeName === 'NullableCalls' && item.sourceFieldName === 'identity') ?? []
const nullableBoundary = report.callableBoundaries?.find(item => item.sourceTypeName === 'NullableCalls' && item.sourceFieldName === 'identity')
if (nullableCalls.length !== 2 || !nullableBoundary
	|| nullableBoundary.proofId !== 'direct-one-nullable-int-static-call-v1'
	|| nullableBoundary.arguments?.length !== 1
	|| !isIdentity(nullableBoundary.arguments[0], 'Null<Int>', 'Obj.t')
	|| !isIdentity(nullableBoundary.result, 'Null<Int>', 'Obj.t')) {
	throw new Error('the lowering report did not seal the exact Null<Int> callable definition')
}
const preserveCall = nullableCalls.find(call => call.arguments?.[0]?.conversion === 'preserve-nullable-int-carrier')
if (!preserveCall
	|| preserveCall.arguments[0].inputSemanticTypeId !== 'Null<Int>'
	|| preserveCall.arguments[0].inputCarrierTypeId !== 'Obj.t'
	|| preserveCall.arguments[0].outputSemanticTypeId !== 'Null<Int>'
	|| preserveCall.arguments[0].outputCarrierTypeId !== 'Obj.t'
	|| preserveCall.arguments[0].proofId !== 'nullable-int-call-carrier-preserve-v1'
	|| !isIdentity(preserveCall.result, 'Null<Int>', 'Obj.t')) {
	throw new Error('the existing nullable argument was not recorded as an exact carrier-preserving crossing')
}
const boxCall = nullableCalls.find(call => call.arguments?.[0]?.conversion === 'box-exact-int-to-nullable-int')
if (!boxCall
	|| boxCall.arguments[0].inputSemanticTypeId !== 'Int'
	|| boxCall.arguments[0].inputCarrierTypeId !== 'int'
	|| boxCall.arguments[0].inputRepresentationId !== 'representation:Int:internal-value'
	|| boxCall.arguments[0].outputSemanticTypeId !== 'Null<Int>'
	|| boxCall.arguments[0].outputCarrierTypeId !== 'Obj.t'
	|| boxCall.arguments[0].outputRepresentationId !== 'representation:Null<Int>:internal-value'
	|| boxCall.arguments[0].proofId !== 'nullable-int-call-box-v1'
	|| !isIdentity(boxCall.result, 'Null<Int>', 'Obj.t')) {
	throw new Error('the exact Int argument was not recorded as one directional box into Null<Int>')
}
for (const call of nullableCalls) {
	if (call.proofId !== 'direct-one-nullable-int-static-call-v1'
		|| call.arguments?.length !== 1
		|| call.evaluationSchedule?.length !== 2
		|| call.evaluationSchedule[0]?.kind !== 'materialize-argument'
		|| call.evaluationSchedule[0]?.argumentIndex !== 0
		|| typeof call.evaluationSchedule[0]?.slotId !== 'string'
		|| call.evaluationSchedule[1]?.kind !== 'invoke-callee') {
		throw new Error('the exact Null<Int> call does not materialize its argument before invocation')
	}
}
const boolCalls = report.calls?.filter(item => item.sourceTypeName === 'BoolCalls' && item.sourceFieldName === 'negate') ?? []
const boolBoundary = report.callableBoundaries?.find(item => item.sourceTypeName === 'BoolCalls' && item.sourceFieldName === 'negate')
if (boolCalls.length !== 1 || !boolBoundary
	|| boolBoundary.proofId !== 'direct-one-bool-static-call-v1'
	|| boolBoundary.arguments?.length !== 1
	|| !isIdentity(boolBoundary.arguments[0], 'Bool', 'bool')
	|| !isIdentity(boolBoundary.result, 'Bool', 'bool')) {
	throw new Error('the lowering report did not seal the exact Bool callable definition')
}
const boolCall = boolCalls[0]
if (boolCall.proofId !== 'direct-one-bool-static-call-v1'
	|| boolCall.arguments?.length !== 1
	|| !isIdentity(boolCall.arguments[0], 'Bool', 'bool')
	|| !isIdentity(boolCall.result, 'Bool', 'bool')
	|| boolCall.evaluationSchedule?.length !== 2
	|| boolCall.evaluationSchedule[0]?.kind !== 'materialize-argument'
	|| boolCall.evaluationSchedule[0]?.argumentIndex !== 0
	|| typeof boolCall.evaluationSchedule[0]?.slotId !== 'string'
	|| boolCall.evaluationSchedule[1]?.kind !== 'invoke-callee') {
	throw new Error('the exact Bool call did not retain its identity crossing and evaluate-before-invoke schedule')
}
const nullableBoolCalls = report.calls?.filter(
	item => item.sourceTypeName === 'BoolCalls' && item.sourceFieldName === 'identityNullable'
) ?? []
const nullableBoolBoundary = report.callableBoundaries?.find(
	item => item.sourceTypeName === 'BoolCalls' && item.sourceFieldName === 'identityNullable'
)
if (nullableBoolCalls.length !== 3 || !nullableBoolBoundary
	|| nullableBoolBoundary.proofId !== 'direct-one-nullable-bool-static-call-v1'
	|| nullableBoolBoundary.arguments?.length !== 1
	|| !isIdentity(nullableBoolBoundary.arguments[0], 'Null<Bool>', 'Obj.t')
	|| !isIdentity(nullableBoolBoundary.result, 'Null<Bool>', 'Obj.t')) {
	throw new Error('the lowering report did not seal the exact Null<Bool> callable definition')
}
const nullableBoolPreserves = nullableBoolCalls.filter(
	call => call.arguments?.[0]?.conversion === 'preserve-nullable-bool-carrier'
)
if (nullableBoolPreserves.length !== 2 || nullableBoolPreserves.some(call =>
	call.arguments[0].inputSemanticTypeId !== 'Null<Bool>'
	|| call.arguments[0].inputCarrierTypeId !== 'Obj.t'
	|| call.arguments[0].inputRepresentationId !== 'representation:Null<Bool>:internal-value'
	|| call.arguments[0].outputSemanticTypeId !== 'Null<Bool>'
	|| call.arguments[0].outputCarrierTypeId !== 'Obj.t'
	|| call.arguments[0].outputRepresentationId !== 'representation:Null<Bool>:internal-value'
	|| call.arguments[0].proofId !== 'nullable-bool-call-carrier-preserve-v1'
	|| !isIdentity(call.result, 'Null<Bool>', 'Obj.t'))) {
	throw new Error('the existing nullable Bool arguments were not recorded as exact carrier-preserving crossings')
}
const nullableBoolBoxes = nullableBoolCalls.filter(
	call => call.arguments?.[0]?.conversion === 'box-exact-bool-to-nullable-bool'
)
if (nullableBoolBoxes.length !== 1) {
	throw new Error('the lowering report must contain exactly one Bool-to-Null<Bool> box crossing')
}
const nullableBoolBox = nullableBoolBoxes[0]
if (nullableBoolBox.arguments[0].inputSemanticTypeId !== 'Bool'
	|| nullableBoolBox.arguments[0].inputCarrierTypeId !== 'bool'
	|| nullableBoolBox.arguments[0].inputRepresentationId !== 'representation:Bool:internal-value'
	|| nullableBoolBox.arguments[0].outputSemanticTypeId !== 'Null<Bool>'
	|| nullableBoolBox.arguments[0].outputCarrierTypeId !== 'Obj.t'
	|| nullableBoolBox.arguments[0].outputRepresentationId !== 'representation:Null<Bool>:internal-value'
	|| nullableBoolBox.arguments[0].proofId !== 'nullable-bool-call-box-v1'
	|| !isIdentity(nullableBoolBox.result, 'Null<Bool>', 'Obj.t')) {
	throw new Error('the exact Bool argument was not recorded as one directional box into Null<Bool>')
}
for (const call of nullableBoolCalls) {
	if (call.proofId !== 'direct-one-nullable-bool-static-call-v1'
		|| call.arguments?.length !== 1
		|| call.evaluationSchedule?.length !== 2
		|| call.evaluationSchedule[0]?.kind !== 'materialize-argument'
		|| call.evaluationSchedule[0]?.argumentIndex !== 0
		|| typeof call.evaluationSchedule[0]?.slotId !== 'string'
		|| call.evaluationSchedule[1]?.kind !== 'invoke-callee'
		|| call.evaluationSchedule[1]?.argumentIndex !== null
		|| call.evaluationSchedule[1]?.slotId !== null) {
		throw new Error('the exact Null<Bool> call does not materialize its argument before invocation')
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
