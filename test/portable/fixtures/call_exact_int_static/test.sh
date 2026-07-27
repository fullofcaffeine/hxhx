#!/usr/bin/env bash
set -euo pipefail

arithmetic_source="out/Arithmetic.ml"
nullable_source="out/NullableCalls.ml"
bool_source="out/BoolCalls.ml"
mixed_source="out/MixedCalls.ml"
zero_source="out/ZeroArgCalls.ml"
optional_source="out/OptionalCalls.ml"
void_source="out/VoidCalls.ml"
main_source="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$arithmetic_source" ] || [ ! -f "$nullable_source" ] || [ ! -f "$bool_source" ] || [ ! -f "$mixed_source" ] || [ ! -f "$zero_source" ] || [ ! -f "$optional_source" ] || [ ! -f "$void_source" ] || [ ! -f "$main_source" ] || [ ! -f "$report_file" ]; then
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
if ! grep -q '^let choose = fun (count : int) (enabled : Obj.t) ->' "$mixed_source"; then
	echo "The mixed callable must independently select int and Obj.t parameter carriers" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = let __call_arg_0_[0-9]+ = "preserve" in let __call_arg_1_[0-9]+ = 41 in mixedCount __call_arg_0_[0-9]+ __call_arg_1_[0-9]+ in let __call_arg_1_[0-9]+ = let __call_arg_0_[0-9]+ = existingMixedFlag in observeExistingMixedFlag __call_arg_0_[0-9]+ in MixedCalls\.choose __call_arg_0_[0-9]+ __call_arg_1_[0-9]+' "$main_source"; then
	echo "The mixed preserve call must evaluate, bind, and preserve both carriers in source order" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = let __call_arg_0_[0-9]+ = "box" in let __call_arg_1_[0-9]+ = 42 in mixedCount __call_arg_0_[0-9]+ __call_arg_1_[0-9]+ in let __call_arg_1_[0-9]+ = Obj\.repr \(exactMixedFlag \(\)\) in MixedCalls\.choose __call_arg_0_[0-9]+ __call_arg_1_[0-9]+' "$main_source"; then
	echo "The mixed box call must evaluate its exact Bool once and box it once after the Int argument" >&2
	exit 1
fi
if grep -Eq 'Obj\.repr \(Obj\.repr \(exactMixedFlag \(\)\)\)' "$main_source"; then
	echo "The mixed signature matrix must not box the exact Bool argument twice" >&2
	exit 1
fi
if ! grep -q '^let chooseMany = fun (prefix : int) (enabled : Obj.t) (invert : bool) (fallback : Obj.t) ->' "$mixed_source"; then
	echo "The positive-arity callable must independently select all four parameter carriers" >&2
	exit 1
fi
if ! grep -Eq 'let preservedMany = let __call_arg_0_[0-9]+ = let __call_arg_0_[0-9]+ = "many-preserve" in let __call_arg_1_[0-9]+ = 83 in mixedCount __call_arg_0_[0-9]+ __call_arg_1_[0-9]+ in let __call_arg_1_[0-9]+ = let __call_arg_0_[0-9]+ = existingMixedFlag in observeExistingMixedFlag __call_arg_0_[0-9]+ in let __call_arg_2_[0-9]+ = let __call_arg_0_[0-9]+ = "preserve" in let __call_arg_1_[0-9]+ = true in mixedDecision __call_arg_0_[0-9]+ __call_arg_1_[0-9]+ in let __call_arg_3_[0-9]+ = let __call_arg_0_[0-9]+ = existingMixedFallback in observeExistingMixedFallback __call_arg_0_[0-9]+ in MixedCalls\.chooseMany __call_arg_0_[0-9]+ __call_arg_1_[0-9]+ __call_arg_2_[0-9]+ __call_arg_3_[0-9]+' "$main_source"; then
	echo "The four-argument preserve call must evaluate, bind, and preserve every carrier in source order" >&2
	exit 1
fi
if ! grep -Eq 'let boxedMany = let __call_arg_0_[0-9]+ = let __call_arg_0_[0-9]+ = "many-box" in let __call_arg_1_[0-9]+ = 84 in mixedCount __call_arg_0_[0-9]+ __call_arg_1_[0-9]+ in let __call_arg_1_[0-9]+ = Obj\.repr \(exactMixedFlag \(\)\) in let __call_arg_2_[0-9]+ = let __call_arg_0_[0-9]+ = "box" in let __call_arg_1_[0-9]+ = true in mixedDecision __call_arg_0_[0-9]+ __call_arg_1_[0-9]+ in let __call_arg_3_[0-9]+ = Obj\.repr \(exactMixedFallback \(\)\) in MixedCalls\.chooseMany __call_arg_0_[0-9]+ __call_arg_1_[0-9]+ __call_arg_2_[0-9]+ __call_arg_3_[0-9]+' "$main_source"; then
	echo "The four-argument box call must evaluate each source argument once and box only the selected nullable crossings" >&2
	exit 1
fi
if grep -Eq 'Obj\.repr \(Obj\.repr \((exactMixedFlag|exactMixedFallback) \(\)\)\)' "$main_source"; then
	echo "The positive-arity signature matrix must not box an exact primitive argument twice" >&2
	exit 1
fi
for zero_method in exactCount exactFlag nullableCount nullableFlag; do
	if ! grep -q "^let ${zero_method} = fun () ->" "$zero_source"; then
		echo "The zero-argument callable ${zero_method} must use an explicit OCaml unit parameter" >&2
		exit 1
	fi
	if ! grep -Eq "ZeroArgCalls\\.${zero_method} \\(\\)" "$main_source"; then
		echo "The zero-argument call ${zero_method} must invoke its target with OCaml unit" >&2
		exit 1
	fi
done
if grep -Eq 'ZeroArgCalls\.(exactCount|exactFlag|nullableCount|nullableFlag)([^ (]|$)' "$main_source"; then
	echo "A zero-argument source call must not lower to a bare OCaml function value" >&2
	exit 1
fi
if ! grep -Eq '^let nullableFlag = fun \(\) -> \(Obj\.repr \(\(' "$zero_source"; then
	echo "The raw Bool result must cross the sealed Null<Bool> callable carrier exactly once" >&2
	exit 1
fi
if grep -Eq 'let result.*Obj\.t|Obj\.repr \(Obj\.repr' "$zero_source"; then
	echo "The callable result conversion must not rely on an intermediate local or box twice" >&2
	exit 1
fi
if ! grep -q '^let optionalInt = fun (value : Obj.t) ->' "$optional_source" \
	|| ! grep -q '^let optionalBool = fun (value : Obj.t) ->' "$optional_source"; then
	echo "Optional Int and Bool declarations must expose their Haxe Null<T> boundary as Obj.t" >&2
	exit 1
fi
if ! grep -q '^let optionalString = fun (value : string) ->' "$optional_source"; then
	echo "The optional String declaration must retain the exact Haxe String carrier" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = HxRuntime\.hx_null in OptionalCalls\.optionalInt __call_arg_0_[0-9]+' "$main_source" \
	|| ! grep -Eq 'let __call_arg_0_[0-9]+ = HxRuntime\.hx_null in OptionalCalls\.optionalBool __call_arg_0_[0-9]+' "$main_source"; then
	echo "Omitted optional primitive arguments must materialize the selected null carrier before invocation" >&2
	exit 1
fi
if [ "$(grep -Ec 'let __call_arg_0_[0-9]+ = HxString\.hx_null_string in OptionalCalls\.optionalString __call_arg_0_[0-9]+' "$main_source")" -ne 2 ]; then
	echo "Omitted and explicitly null optional Strings must each materialize the dedicated Haxe String null sentinel" >&2
	exit 1
fi
if grep -Eq 'let __call_arg_0_[0-9]+ = (HxRuntime\.hx_null|\"\") in OptionalCalls\.optionalString __call_arg_0_[0-9]+' "$main_source"; then
	echo "An omitted optional String must not use the object null carrier or an empty string" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = Obj\.repr \(optionalIntSource \(\)\) in OptionalCalls\.optionalInt __call_arg_0_[0-9]+' "$main_source" \
	|| ! grep -Eq 'let __call_arg_0_[0-9]+ = Obj\.repr \(optionalBoolSource \(\)\) in OptionalCalls\.optionalBool __call_arg_0_[0-9]+' "$main_source"; then
	echo "Supplied exact optional primitive arguments must be evaluated once and boxed once" >&2
	exit 1
fi
if grep -Eq 'Obj\.repr \(Obj\.repr \(optional(Int|Bool)Source \(\)\)\)' "$main_source"; then
	echo "A supplied optional primitive argument must not be boxed twice" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = optionalStringSource \(\) in OptionalCalls\.optionalString __call_arg_0_[0-9]+' "$main_source"; then
	echo "A supplied optional String must be evaluated once and preserve its exact carrier" >&2
	exit 1
fi
if ! grep -q '^let noArguments = fun () ->' "$void_source"; then
	echo "The zero-argument Void callable must use an explicit OCaml unit parameter" >&2
	exit 1
fi
if ! grep -Eq 'VoidCalls\.noArguments \(\)' "$main_source"; then
	echo "The zero-argument Void call must invoke its target with OCaml unit" >&2
	exit 1
fi
if ! grep -Eq 'let __call_arg_0_[0-9]+ = voidIntSource \(\) in let __call_arg_1_[0-9]+ = voidBoolSource \(\) in let __call_arg_2_[0-9]+ = voidStringSource \(\) in VoidCalls\.withArguments __call_arg_0_[0-9]+ __call_arg_1_[0-9]+ __call_arg_2_[0-9]+' "$main_source"; then
	echo "The positive-arity Void call must evaluate and bind every argument before invocation" >&2
	exit 1
fi

negative_log="$(mktemp)"
rm -rf negative-out
if haxe negative.hxml >"$negative_log" 2>&1; then
	echo "An early Bool return unexpectedly bypassed the sealed result-control boundary" >&2
	rm -f "$negative_log"
	exit 1
fi
if ! grep -Fq '[ocaml-call:result-control-unsealed]' "$negative_log"; then
	echo "The rejected early result conversion did not report its stable ownership diagnostic" >&2
	cat "$negative_log" >&2
	rm -f "$negative_log"
	exit 1
fi
if [ -f negative-out/ResultControlRejected.ml ]; then
	echo "The rejected early result conversion reached OCaml syntax output" >&2
	rm -f "$negative_log"
	exit 1
fi
rm -f "$negative_log"

optional_negative_log="$(mktemp)"
rm -rf optional-negative-out
if haxe optional-negative.hxml >"$optional_negative_log" 2>&1; then
	echo "An optional static-initializer call unexpectedly fell back to builder-time argument padding" >&2
	rm -f "$optional_negative_log"
	exit 1
fi
if ! grep -Fq '[ocaml-call:plan-invariant]' "$optional_negative_log" \
	|| ! grep -Fq 'reached syntax without its sealed occurrence plan' "$optional_negative_log"; then
	echo "The unplanned optional call did not report the stable hard-cut diagnostic" >&2
	cat "$optional_negative_log" >&2
	rm -f "$optional_negative_log"
	exit 1
fi
if [ -f optional-negative-out/OptionalOccurrenceRejected.ml ]; then
	echo "The unplanned optional call reached OCaml module output" >&2
	rm -f "$optional_negative_log"
	exit 1
fi
rm -f "$optional_negative_log"

void_negative_log="$(mktemp)"
rm -rf void-negative-out
if haxe void-negative.hxml >"$void_negative_log" 2>&1; then
	echo "A Void static-initializer call unexpectedly fell back to unplanned target syntax" >&2
	rm -f "$void_negative_log"
	exit 1
fi
if ! grep -Fq '[ocaml-call:plan-invariant]' "$void_negative_log" \
	|| ! grep -Fq 'reached syntax without its sealed occurrence plan' "$void_negative_log"; then
	echo "The unplanned Void call did not report the stable hard-cut diagnostic" >&2
	cat "$void_negative_log" >&2
	rm -f "$void_negative_log"
	exit 1
fi
if [ -f void-negative-out/VoidOccurrenceRejected.ml ]; then
	echo "The unplanned Void call reached OCaml module output" >&2
	rm -f "$void_negative_log"
	exit 1
fi
rm -f "$void_negative_log"

node - "$report_file" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (report.schemaVersion !== 30 || report.callModel !== 'typed-ocaml-directional-call-boundary-v16') {
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
function isBoxBoolToNullable(value) {
	return value?.inputSemanticTypeId === 'Bool'
		&& value?.inputCarrierTypeId === 'bool'
		&& value?.inputRepresentationId === 'representation:Bool:internal-value'
		&& value?.outputSemanticTypeId === 'Null<Bool>'
		&& value?.outputCarrierTypeId === 'Obj.t'
		&& value?.outputRepresentationId === 'representation:Null<Bool>:internal-value'
		&& value?.conversion === 'box-exact-bool-to-nullable-bool'
		&& value?.proofId === 'nullable-bool-call-box-v1'
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
			|| boundary.result?.outputRepresentationId !== call.result.inputRepresentationId) {
			throw new Error(`call ${fieldName} does not match an independently sealed callable definition`)
		}
	}
}
const signatureProofId = 'direct-static-representation-signature-v3'
if (report.calls.some(call => call.kind === 'direct-static-haxe-method' && call.proofId !== signatureProofId)
	|| report.callableBoundaries.some(boundary =>
		boundary.kind === 'direct-static-haxe-method' && boundary.proofId !== signatureProofId)) {
	throw new Error('an admitted direct-static call retained a legacy per-family proof')
}
const fixtureTypeNames = new Set(['Arithmetic', 'NullableCalls', 'BoolCalls', 'MixedCalls', 'ZeroArgCalls', 'OptionalCalls', 'VoidCalls'])
for (const owner of [...report.calls, ...report.callableBoundaries].filter(owner => fixtureTypeNames.has(owner.sourceTypeName))) {
	if (owner.resultKind === 'value' && owner.result?.parameterOptional !== false) {
		throw new Error(`call owner ${owner.id} marked its result as an optional parameter`)
	}
	const optionalArguments = owner.arguments?.filter(argument => argument.parameterOptional) ?? []
	if (optionalArguments.length > 1
		|| (optionalArguments.length === 1
			&& (owner.sourceTypeName !== 'OptionalCalls'
				|| optionalArguments[0].index !== owner.arguments.length - 1))) {
		throw new Error(`call owner ${owner.id} has an unsupported optional-parameter shape`)
	}
	if (owner.sourceTypeName !== 'OptionalCalls' && owner.arguments?.some(argument => argument.parameterOptional !== false)) {
		throw new Error(`non-optional call owner ${owner.id} changed parameter optionality`)
	}
}
for (const call of report.calls.filter(item => item.kind === 'direct-static-haxe-method')) {
	let sourceArgumentIndex = 0
	for (let index = 0; index < call.arguments.length; index++) {
		const argument = call.arguments[index]
		const omitted = argument.conversion === 'materialize-omitted-nullable-int'
			|| argument.conversion === 'materialize-omitted-nullable-bool'
			|| argument.conversion === 'materialize-omitted-string'
		const step = call.evaluationSchedule?.[index]
		if (step?.kind !== (omitted ? 'materialize-omitted-argument' : 'materialize-argument')
			|| step.argumentIndex !== index
			|| step.sourceArgumentIndex !== (omitted ? null : sourceArgumentIndex++)
			|| typeof step.slotId !== 'string') {
			throw new Error(`call ${call.id} has an invalid parameter/source argument schedule at index ${index}`)
		}
	}
	const invocation = call.evaluationSchedule?.[call.arguments.length]
	if (invocation?.kind !== 'invoke-callee'
		|| invocation.argumentIndex !== null
		|| invocation.sourceArgumentIndex !== null
		|| invocation.slotId !== null) {
		throw new Error(`call ${call.id} has an invalid final invocation step`)
	}
}
verifyCalls('increment', 1, signatureProofId, 1)
verifyCalls('add', 2, signatureProofId, 2)
function verifyZeroCall(fieldName, semanticTypeId, carrierTypeId, boundaryResult = null) {
	const calls = report.calls?.filter(item => item.sourceTypeName === 'ZeroArgCalls' && item.sourceFieldName === fieldName) ?? []
	const boundary = report.callableBoundaries?.find(
		item => item.sourceTypeName === 'ZeroArgCalls' && item.sourceFieldName === fieldName
	)
	if (calls.length !== 1 || !boundary
		|| calls[0].proofId !== signatureProofId
		|| calls[0].arguments?.length !== 0
		|| !isIdentity(calls[0].result, semanticTypeId, carrierTypeId)
		|| calls[0].evaluationSchedule?.length !== 1
		|| calls[0].evaluationSchedule[0]?.kind !== 'invoke-callee'
		|| calls[0].evaluationSchedule[0]?.argumentIndex !== null
		|| calls[0].evaluationSchedule[0]?.slotId !== null
		|| boundary.proofId !== signatureProofId
		|| boundary.arguments?.length !== 0
		|| !(boundaryResult ? boundaryResult(boundary.result) : isIdentity(boundary.result, semanticTypeId, carrierTypeId))) {
		throw new Error(`the lowering report did not seal zero-argument call ${fieldName} with its exact ${semanticTypeId} result`)
	}
}
verifyZeroCall('exactCount', 'Int', 'int')
verifyZeroCall('exactFlag', 'Bool', 'bool')
verifyZeroCall('nullableCount', 'Null<Int>', 'Obj.t')
verifyZeroCall('nullableFlag', 'Null<Bool>', 'Obj.t', isBoxBoolToNullable)

const nullableCalls = report.calls?.filter(item => item.sourceTypeName === 'NullableCalls' && item.sourceFieldName === 'identity') ?? []
const nullableBoundary = report.callableBoundaries?.find(item => item.sourceTypeName === 'NullableCalls' && item.sourceFieldName === 'identity')
if (nullableCalls.length !== 2 || !nullableBoundary
	|| nullableBoundary.proofId !== signatureProofId
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
	if (call.proofId !== signatureProofId
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
	|| boolBoundary.proofId !== signatureProofId
	|| boolBoundary.arguments?.length !== 1
	|| !isIdentity(boolBoundary.arguments[0], 'Bool', 'bool')
	|| !isIdentity(boolBoundary.result, 'Bool', 'bool')) {
	throw new Error('the lowering report did not seal the exact Bool callable definition')
}
const boolCall = boolCalls[0]
if (boolCall.proofId !== signatureProofId
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
	|| nullableBoolBoundary.proofId !== signatureProofId
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
	if (call.proofId !== signatureProofId
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
const mixedCalls = report.calls?.filter(item => item.sourceTypeName === 'MixedCalls' && item.sourceFieldName === 'choose') ?? []
const mixedBoundary = report.callableBoundaries?.find(item => item.sourceTypeName === 'MixedCalls' && item.sourceFieldName === 'choose')
if (mixedCalls.length !== 2 || !mixedBoundary
	|| mixedBoundary.proofId !== signatureProofId
	|| mixedBoundary.arguments?.length !== 2
	|| !isIdentity(mixedBoundary.arguments[0], 'Int', 'int')
	|| !isIdentity(mixedBoundary.arguments[1], 'Null<Bool>', 'Obj.t')
	|| !isIdentity(mixedBoundary.result, 'Null<Int>', 'Obj.t')) {
	throw new Error('the lowering report did not seal the mixed Int, Null<Bool> -> Null<Int> callable definition')
}
const mixedPreserve = mixedCalls.find(call => call.arguments?.[1]?.conversion === 'preserve-nullable-bool-carrier')
const mixedBox = mixedCalls.find(call => call.arguments?.[1]?.conversion === 'box-exact-bool-to-nullable-bool')
if (!mixedPreserve || !mixedBox
	|| !isIdentity(mixedPreserve.arguments[0], 'Int', 'int')
	|| !isIdentity(mixedPreserve.result, 'Null<Int>', 'Obj.t')
	|| mixedPreserve.arguments[1].inputSemanticTypeId !== 'Null<Bool>'
	|| mixedPreserve.arguments[1].inputCarrierTypeId !== 'Obj.t'
	|| mixedPreserve.arguments[1].outputSemanticTypeId !== 'Null<Bool>'
	|| mixedPreserve.arguments[1].outputCarrierTypeId !== 'Obj.t'
	|| mixedPreserve.arguments[1].proofId !== 'nullable-bool-call-carrier-preserve-v1'
	|| !isIdentity(mixedBox.arguments[0], 'Int', 'int')
	|| !isIdentity(mixedBox.result, 'Null<Int>', 'Obj.t')
	|| mixedBox.arguments[1].inputSemanticTypeId !== 'Bool'
	|| mixedBox.arguments[1].inputCarrierTypeId !== 'bool'
	|| mixedBox.arguments[1].outputSemanticTypeId !== 'Null<Bool>'
	|| mixedBox.arguments[1].outputCarrierTypeId !== 'Obj.t'
	|| mixedBox.arguments[1].proofId !== 'nullable-bool-call-box-v1') {
	throw new Error('the mixed call occurrences did not preserve their independent directional crossings')
}
for (const call of mixedCalls) {
	if (call.proofId !== signatureProofId
		|| call.arguments?.length !== 2
		|| call.evaluationSchedule?.length !== 3
		|| call.evaluationSchedule[0]?.kind !== 'materialize-argument'
		|| call.evaluationSchedule[0]?.argumentIndex !== 0
		|| call.evaluationSchedule[1]?.kind !== 'materialize-argument'
		|| call.evaluationSchedule[1]?.argumentIndex !== 1
		|| call.evaluationSchedule[2]?.kind !== 'invoke-callee') {
		throw new Error('the mixed signature did not retain its evaluate-bind-invoke schedule')
	}
}
const positiveArityCalls = report.calls?.filter(item => item.sourceTypeName === 'MixedCalls' && item.sourceFieldName === 'chooseMany') ?? []
const positiveArityBoundary = report.callableBoundaries?.find(
	item => item.sourceTypeName === 'MixedCalls' && item.sourceFieldName === 'chooseMany'
)
if (positiveArityCalls.length !== 2 || !positiveArityBoundary
	|| positiveArityBoundary.proofId !== signatureProofId
	|| positiveArityBoundary.arguments?.length !== 4
	|| !isIdentity(positiveArityBoundary.arguments[0], 'Int', 'int')
	|| !isIdentity(positiveArityBoundary.arguments[1], 'Null<Bool>', 'Obj.t')
	|| !isIdentity(positiveArityBoundary.arguments[2], 'Bool', 'bool')
	|| !isIdentity(positiveArityBoundary.arguments[3], 'Null<Int>', 'Obj.t')
	|| !isIdentity(positiveArityBoundary.result, 'Null<Int>', 'Obj.t')) {
	throw new Error('the lowering report did not seal the four-argument mixed callable definition')
}
const positiveArityPreserve = positiveArityCalls.find(call =>
	call.arguments?.[1]?.conversion === 'preserve-nullable-bool-carrier'
	&& call.arguments?.[3]?.conversion === 'preserve-nullable-int-carrier'
)
const positiveArityBox = positiveArityCalls.find(call =>
	call.arguments?.[1]?.conversion === 'box-exact-bool-to-nullable-bool'
	&& call.arguments?.[3]?.conversion === 'box-exact-int-to-nullable-int'
)
if (!positiveArityPreserve || !positiveArityBox
	|| !isIdentity(positiveArityPreserve.arguments[0], 'Int', 'int')
	|| !isIdentity(positiveArityPreserve.arguments[2], 'Bool', 'bool')
	|| !isIdentity(positiveArityPreserve.result, 'Null<Int>', 'Obj.t')
	|| !isIdentity(positiveArityBox.arguments[0], 'Int', 'int')
	|| !isIdentity(positiveArityBox.arguments[2], 'Bool', 'bool')
	|| !isIdentity(positiveArityBox.result, 'Null<Int>', 'Obj.t')) {
	throw new Error('the four-argument calls did not retain their independent directional crossings')
}
for (const call of positiveArityCalls) {
	if (call.proofId !== signatureProofId
		|| call.arguments?.length !== 4
		|| call.evaluationSchedule?.length !== 5) {
		throw new Error('the positive-arity call did not retain its complete sealed argument vector')
	}
	for (let index = 0; index < 4; index++) {
		if (call.evaluationSchedule[index]?.kind !== 'materialize-argument'
			|| call.evaluationSchedule[index]?.argumentIndex !== index) {
			throw new Error(`the positive-arity call did not materialize source argument ${index} in order`)
		}
	}
	if (call.evaluationSchedule[4]?.kind !== 'invoke-callee'
		|| call.evaluationSchedule[4]?.argumentIndex !== null
		|| call.evaluationSchedule[4]?.slotId !== null) {
		throw new Error('the positive-arity call did not invoke exactly once after all argument bindings')
	}
}
function verifyOptionalCalls(fieldName, semanticTypeId, resultSemanticTypeId, resultCarrierTypeId) {
	const calls = report.calls?.filter(item => item.sourceTypeName === 'OptionalCalls' && item.sourceFieldName === fieldName) ?? []
	const boundary = report.callableBoundaries?.find(
		item => item.sourceTypeName === 'OptionalCalls' && item.sourceFieldName === fieldName
	)
	const suffix = semanticTypeId === 'Null<Int>' ? 'int' : 'bool'
	if (calls.length !== 4 || !boundary
		|| boundary.arguments?.length !== 1
		|| boundary.arguments[0]?.parameterOptional !== true
		|| !isIdentity(boundary.arguments[0], semanticTypeId, 'Obj.t')
		|| !isIdentity(boundary.result, resultSemanticTypeId, resultCarrierTypeId)) {
		throw new Error(`the lowering report did not seal optional ${fieldName} with its full callable shape`)
	}
	const omitted = calls.filter(call => call.arguments?.[0]?.conversion === `materialize-omitted-nullable-${suffix}`)
	const preserved = calls.filter(call => call.arguments?.[0]?.conversion === `preserve-nullable-${suffix}-carrier`)
	const boxed = calls.filter(call => call.arguments?.[0]?.conversion === `box-exact-${suffix}-to-nullable-${suffix}`)
	if (omitted.length !== 1 || preserved.length !== 2 || boxed.length !== 1) {
		throw new Error(`optional ${fieldName} did not distinguish omission, explicit/nullable values, and an exact primitive`)
	}
	const omittedCall = omitted[0]
	const omittedArgument = omittedCall.arguments[0]
	if (omittedArgument.parameterOptional !== true
		|| omittedArgument.proofId !== `omitted-nullable-${suffix}-call-materialization-v1`
		|| omittedCall.evaluationSchedule?.length !== 2
		|| omittedCall.evaluationSchedule[0]?.kind !== 'materialize-omitted-argument'
		|| omittedCall.evaluationSchedule[0]?.argumentIndex !== 0
		|| omittedCall.evaluationSchedule[0]?.sourceArgumentIndex !== null
		|| typeof omittedCall.evaluationSchedule[0]?.slotId !== 'string') {
		throw new Error(`optional ${fieldName} omission does not own one source-free null-carrier materialization`)
	}
	for (const call of [...preserved, ...boxed]) {
		if (call.arguments[0]?.parameterOptional !== true
			|| call.evaluationSchedule?.length !== 2
			|| call.evaluationSchedule[0]?.kind !== 'materialize-argument'
			|| call.evaluationSchedule[0]?.argumentIndex !== 0
			|| call.evaluationSchedule[0]?.sourceArgumentIndex !== 0) {
			throw new Error(`supplied optional ${fieldName} did not retain its source argument materialization`)
		}
	}
	for (const call of calls) {
		const invocation = call.evaluationSchedule?.[1]
		if (invocation?.kind !== 'invoke-callee'
			|| invocation.argumentIndex !== null
			|| invocation.sourceArgumentIndex !== null
			|| invocation.slotId !== null) {
			throw new Error(`optional ${fieldName} did not invoke exactly once after materialization`)
		}
	}
}
verifyOptionalCalls('optionalInt', 'Null<Int>', 'Int', 'int')
verifyOptionalCalls('optionalBool', 'Null<Bool>', 'Bool', 'bool')
function verifyOptionalString() {
	const calls = report.calls?.filter(item => item.sourceTypeName === 'OptionalCalls' && item.sourceFieldName === 'optionalString') ?? []
	const boundary = report.callableBoundaries?.find(
		item => item.sourceTypeName === 'OptionalCalls' && item.sourceFieldName === 'optionalString'
	)
	if (calls.length !== 3 || !boundary
		|| boundary.arguments?.length !== 1
		|| boundary.arguments[0]?.parameterOptional !== true
		|| !isIdentity(boundary.arguments[0], 'String', 'string')
		|| !isIdentity(boundary.result, 'String', 'string')) {
		throw new Error('the lowering report did not seal optional String with its exact callable shape')
	}
	const omitted = calls.filter(call => call.arguments?.[0]?.conversion === 'materialize-omitted-string')
	const explicitNull = calls.filter(call => call.arguments?.[0]?.conversion === 'materialize-explicit-null-string')
	const supplied = calls.filter(call => call.arguments?.[0]?.conversion === 'identity')
	if (omitted.length !== 1 || explicitNull.length !== 1 || supplied.length !== 1) {
		throw new Error('optional String did not distinguish omission from explicit null and a supplied value')
	}
	const omittedArgument = omitted[0].arguments[0]
	if (omittedArgument.parameterOptional !== true
		|| omittedArgument.inputSemanticTypeId !== 'String'
		|| omittedArgument.inputCarrierTypeId !== 'string'
		|| omittedArgument.proofId !== 'omitted-string-call-materialization-v1'
		|| omitted[0].evaluationSchedule?.[0]?.kind !== 'materialize-omitted-argument'
		|| omitted[0].evaluationSchedule?.[0]?.sourceArgumentIndex !== null) {
		throw new Error('optional String omission does not own one source-free sentinel materialization')
	}
	if (explicitNull[0].arguments[0]?.proofId !== 'explicit-null-string-call-materialization-v1') {
		throw new Error('the explicitly supplied null String does not own its sentinel materialization proof')
	}
	for (const call of [...explicitNull, ...supplied]) {
		if (call.arguments[0]?.parameterOptional !== true
			|| call.evaluationSchedule?.[0]?.kind !== 'materialize-argument'
			|| call.evaluationSchedule?.[0]?.sourceArgumentIndex !== 0) {
			throw new Error('a supplied optional String did not retain its source argument materialization')
		}
	}
}
verifyOptionalString()
function verifyVoidCall(fieldName, arity) {
	const calls = report.calls?.filter(item => item.sourceTypeName === 'VoidCalls' && item.sourceFieldName === fieldName) ?? []
	const boundary = report.callableBoundaries?.find(
		item => item.sourceTypeName === 'VoidCalls' && item.sourceFieldName === fieldName
	)
	if (calls.length !== 1 || !boundary
		|| calls[0].resultKind !== 'effect-only-void'
		|| calls[0].result !== null
		|| boundary.resultKind !== 'effect-only-void'
		|| boundary.result !== null
		|| calls[0].arguments?.length !== arity
		|| boundary.arguments?.length !== arity
		|| calls[0].evaluationSchedule?.length !== arity + 1
		|| calls[0].evaluationSchedule[arity]?.kind !== 'invoke-callee') {
		throw new Error(`the lowering report did not seal effect-only Void call ${fieldName}`)
	}
}
verifyVoidCall('noArguments', 0)
verifyVoidCall('withArguments', 3)
const instanceOwners = [...report.calls, ...report.callableBoundaries].filter(item =>
	item.sourceTypeName === 'Counter')
if (instanceOwners.length !== 2
	|| instanceOwners.some(item =>
		item.kind !== 'direct-instance-haxe-method'
		|| item.receiver?.outputSemanticTypeId !== 'Counter')) {
	throw new Error('the Counter instance method did not enter only the sealed direct-instance call kind')
}
NODE

repo_root="$(cd ../../../.. && pwd)"
fixture_root="$PWD"
inspection_report="$(mktemp)"
trap 'rm -f "$inspection_report"' EXIT
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
	throw new Error('reflaxe.ocaml inspection rejected the sealed call report')
}
const calls = report.lowering?.calls?.filter(item => item.sourceTypeName === 'MixedCalls' && item.sourceFieldName === 'chooseMany') ?? []
const boundary = report.lowering?.callableBoundaries?.find(
	item => item.sourceTypeName === 'MixedCalls' && item.sourceFieldName === 'chooseMany'
)
if (calls.length !== 2 || calls.some(call => call.arguments?.length !== 4) || boundary?.arguments?.length !== 4) {
	throw new Error('reflaxe.ocaml inspection did not preserve the four-argument call and callable boundary')
}
const zeroCalls = report.lowering?.calls?.filter(item => item.sourceTypeName === 'ZeroArgCalls') ?? []
const zeroBoundaries = report.lowering?.callableBoundaries?.filter(item => item.sourceTypeName === 'ZeroArgCalls') ?? []
if (zeroCalls.length !== 4
	|| zeroCalls.some(call => call.arguments?.length !== 0
		|| call.evaluationSchedule?.length !== 1
		|| call.evaluationSchedule[0]?.kind !== 'invoke-callee')
	|| zeroBoundaries.length !== 4
	|| zeroBoundaries.some(item => item.arguments?.length !== 0)) {
	throw new Error('reflaxe.ocaml inspection did not preserve the zero-argument calls and callable boundaries')
}
const optionalCalls = report.lowering?.calls?.filter(item => item.sourceTypeName === 'OptionalCalls') ?? []
const optionalBoundaries = report.lowering?.callableBoundaries?.filter(item => item.sourceTypeName === 'OptionalCalls') ?? []
if (optionalCalls.length !== 11
	|| optionalBoundaries.length !== 3
	|| optionalBoundaries.some(item => item.arguments?.length !== 1 || item.arguments[0]?.parameterOptional !== true)
	|| optionalCalls.filter(call => call.evaluationSchedule?.[0]?.kind === 'materialize-omitted-argument').length !== 3
	|| optionalCalls.some(call => call.arguments?.[0]?.parameterOptional !== true)) {
	throw new Error('reflaxe.ocaml inspection did not preserve optional primitive/String presence and callable shape')
}
const voidCalls = report.lowering?.calls?.filter(item => item.sourceTypeName === 'VoidCalls') ?? []
const voidBoundaries = report.lowering?.callableBoundaries?.filter(item => item.sourceTypeName === 'VoidCalls') ?? []
if (voidCalls.length !== 2
	|| voidBoundaries.length !== 2
	|| [...voidCalls, ...voidBoundaries].some(item =>
		item.resultKind !== 'effect-only-void' || item.result !== null)) {
	throw new Error('reflaxe.ocaml inspection did not preserve effect-only Void call results')
}
NODE

oracle_output="$(mktemp)"
trap 'rm -f "$inspection_report" "$oracle_output"' EXIT
haxe -cp src --main Main --interp >"$oracle_output"
diff -u expected.stdout "$oracle_output"

echo "EXACT_INT_STATIC_CALL_PLAN:PASS"
