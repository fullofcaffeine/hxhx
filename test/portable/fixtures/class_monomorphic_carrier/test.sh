#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$source_file" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated monomorphic-class source or lowering report" >&2
	exit 1
fi

node - "$source_file" "$report_file" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 26
	|| report.representationScope !== 'exact-int-bool-nullable-string-field-defaults-direct-simple-assignment-array-int-locals-monomorphic-class-v12') {
	fail('unexpected lowering-report schema or representation scope')
}

const decision = report.representations?.find(item =>
	item.id === 'representation:Counter:internal-value')
const capturedDecision = report.representations?.find(item =>
	item.id === 'representation:Counter:captured-local-storage')
if (decision == null
	|| decision.semanticTypeId !== 'Counter'
	|| decision.carrierTypeId !== 'counter_t'
	|| decision.domain !== 'internal-value'
	|| decision.boxingPolicy !== 'nullable-nominal-record-carrier'
	|| decision.identityPolicy !== 'reference-identity'
	|| decision.aliasingPolicy !== 'shared-reference-aliases'
	|| decision.nominalTargetModuleName !== 'Main'
	|| decision.nominalTargetTypeName !== 'counter_t'
	|| !/^sha256:[0-9a-f]{64}$/.test(decision.nominalLayoutRevision)
	|| decision.proof?.id !== `whole-program-monomorphic-nominal-record-v1:${decision.nominalLayoutRevision}`) {
	fail('the exact Counter carrier is not sealed as the expected nominal record')
}
if (capturedDecision == null
	|| capturedDecision.semanticTypeId !== decision.semanticTypeId
	|| capturedDecision.carrierTypeId !== decision.carrierTypeId
	|| capturedDecision.domain !== 'captured-local-storage'
	|| capturedDecision.storageMutationPolicy !== 'shared-local-cell'
	|| capturedDecision.identityPolicy !== decision.identityPolicy
	|| capturedDecision.aliasingPolicy !== decision.aliasingPolicy
	|| capturedDecision.nominalTargetModuleName !== decision.nominalTargetModuleName
	|| capturedDecision.nominalTargetTypeName !== decision.nominalTargetTypeName
	|| capturedDecision.nominalLayoutRevision !== decision.nominalLayoutRevision
	|| capturedDecision.proof?.id !== decision.proof?.id) {
	fail('the captured-and-reassigned Counter local does not reuse the exact nominal record inside one shared cell')
}

const admittedReceivers = (report.plans ?? []).filter(plan =>
	plan.place?.receiverSemanticTypeId === 'Counter'
	&& plan.place?.receiverRepresentationId === decision.id)
if (admittedReceivers.length !== 4
	|| admittedReceivers.some(plan =>
		plan.place.receiverCarrierTypeId !== 'counter_t'
		|| plan.place.kind !== 'instance-field')) {
	fail(`expected four Counter field plans, including the closure read, to consume the sealed receiver, got ${admittedReceivers.length}`)
}

const instanceCalls = (report.calls ?? []).filter(call =>
	call.kind === 'direct-instance-haxe-method'
	&& call.sourceTypeName === 'Counter'
	&& call.sourceFieldName === 'bump')
const constructorCalls = (report.calls ?? []).filter(call =>
	call.kind === 'direct-haxe-constructor'
	&& call.sourceTypeName === 'Counter'
	&& call.sourceFieldName === 'new')
const constructorBoundaries = (report.callableBoundaries ?? []).filter(boundary =>
	boundary.kind === 'direct-haxe-constructor')
const instanceBoundaries = (report.callableBoundaries ?? []).filter(boundary =>
	boundary.kind === 'direct-instance-haxe-method')
if (constructorBoundaries.length !== 1
	|| constructorBoundaries[0].sourceTypeName !== 'Counter'
	|| constructorBoundaries[0].sourceFieldName !== 'new'
	|| constructorBoundaries[0].result?.outputRepresentationId !== decision.id) {
	fail('the report did not seal the exact Counter construction boundary')
}
if (constructorCalls.length !== 9) {
	fail(`expected nine exact Counter constructions across admitted and excluded local-storage cases, got ${constructorCalls.length}`)
}
for (const constructorCall of constructorCalls) {
	if (constructorCall.receiver !== null
		|| constructorCall.arguments?.length !== 1
		|| constructorCall.arguments[0]?.outputSemanticTypeId !== 'Int'
		|| constructorCall.arguments[0]?.outputCarrierTypeId !== 'int'
		|| constructorCall.arguments[0]?.conversion !== 'identity'
		|| constructorCall.resultKind !== 'value'
		|| constructorCall.result?.inputSemanticTypeId !== 'Counter'
		|| constructorCall.result?.inputCarrierTypeId !== 'counter_t'
		|| constructorCall.result?.inputRepresentationId !== decision.id
		|| constructorCall.result?.outputSemanticTypeId !== 'Counter'
		|| constructorCall.result?.outputCarrierTypeId !== 'counter_t'
		|| constructorCall.result?.outputRepresentationId !== decision.id
		|| constructorCall.result?.conversion !== 'identity'
		|| constructorCall.evaluationSchedule?.length !== 2
		|| constructorCall.evaluationSchedule[0]?.kind !== 'materialize-argument'
		|| constructorCall.evaluationSchedule[0]?.argumentIndex !== 0
		|| constructorCall.evaluationSchedule[0]?.sourceArgumentIndex !== 0
		|| typeof constructorCall.evaluationSchedule[0]?.slotId !== 'string'
		|| constructorCall.evaluationSchedule[1]?.kind !== 'invoke-callee') {
		fail('a Counter construction does not preserve its exact argument, result, and evaluation schedule')
	}
}
if (instanceBoundaries.length !== 1
	|| instanceBoundaries[0].sourceTypeName !== 'Counter'
	|| instanceBoundaries[0].sourceFieldName !== 'bump'
	|| instanceBoundaries[0].receiver?.outputRepresentationId !== decision.id) {
	fail('the report admitted an unexpected instance callable boundary')
}
if (instanceCalls.length !== 2) {
	fail(`expected constructor-local and factory-produced Counter.bump calls, got ${instanceCalls.length}`)
}
for (const instanceCall of instanceCalls) {
	if (instanceCall.receiver?.inputSemanticTypeId !== 'Counter'
		|| instanceCall.receiver.inputCarrierTypeId !== 'counter_t'
		|| instanceCall.receiver.inputRepresentationId !== decision.id
		|| instanceCall.receiver.outputSemanticTypeId !== 'Counter'
		|| instanceCall.receiver.outputCarrierTypeId !== 'counter_t'
		|| instanceCall.receiver.outputRepresentationId !== decision.id
		|| instanceCall.receiver.conversion !== 'identity'
		|| instanceCall.evaluationSchedule?.length !== 3
		|| instanceCall.evaluationSchedule[0]?.kind !== 'materialize-receiver'
		|| instanceCall.evaluationSchedule[0]?.argumentIndex !== null
		|| instanceCall.evaluationSchedule[0]?.sourceArgumentIndex !== null
		|| typeof instanceCall.evaluationSchedule[0]?.slotId !== 'string'
		|| instanceCall.evaluationSchedule[1]?.kind !== 'materialize-argument'
		|| instanceCall.evaluationSchedule[1]?.argumentIndex !== 0
		|| instanceCall.evaluationSchedule[1]?.sourceArgumentIndex !== 0
		|| instanceCall.evaluationSchedule[2]?.kind !== 'invoke-callee') {
		fail('a Counter.bump call does not seal receiver-before-argument evaluation')
	}
}

if (!/let counter = let __call_arg_0_\d+ = 6 in counter_create __call_arg_0_\d+ in let read = fun \(\) -> \(counter : counter_t\)\.value/.test(source)) {
	fail('the immutable captured Counter local did not retain its sealed nominal carrier inside the closure')
}
if (!/let reassignedCapturedLocalCase = fun \(\) -> ignore \(\([\s\S]*let counter = ref \(let __call_arg_0_\d+ = 10 in counter_create __call_arg_0_\d+\) in let read = fun \(\) -> \(!counter : counter_t\)\.value/.test(source)
	|| !/let __assign_\d+ = let __call_arg_0_\d+ = 11 in counter_create __call_arg_0_\d+ in \([\s\S]*counter := __assign_\d+/.test(source)) {
	fail('the captured-and-reassigned Counter local did not use one typed nominal ref cell')
}
const reassignedStart = source.indexOf('let reassignedCapturedLocalCase')
const reassignedEnd = source.indexOf('\nlet excludedCarrierBoundaries', reassignedStart)
if (reassignedStart < 0 || reassignedEnd < 0 || source.slice(reassignedStart, reassignedEnd).includes('Obj.magic')) {
	fail('the admitted captured-and-reassigned Counter function still contains a Dynamic carrier cast')
}
if (!/let ordinary = Obj\.magic \(let __call_arg_0_\d+ = 13 in counter_create __call_arg_0_\d+\)/.test(source)
	|| !/let called = ref \(Obj\.magic \(let __call_arg_0_\d+ = 14 in counter_create __call_arg_0_\d+\)\) in let read = fun \(\) -> \(Obj\.magic \(!called\) : counter_t\)\.value/.test(source)
	|| !/let __assign_\d+ = Obj\.magic \(makeCounter \(\)\) in \([\s\S]*called := __assign_\d+/.test(source)) {
	fail('ordinary mutable or call-produced captured Counter boundaries were admitted without their own typed proof')
}
if (!/let counter = let __call_arg_0_\d+ = sourceValue \(\) in counter_create __call_arg_0_\d+/.test(source)) {
	fail('the constructor-local path did not materialize its argument before invoking Counter.create')
}

const requiredSource = [
	'type counter_t = { __hx_type : Obj.t; mutable value : int }',
	'(self : counter_t).value',
	'(counter : counter_t).value',
	'let __call_arg_0_',
	'counter_create __call_arg_0_',
	'let __call_receiver_',
	'counter_bump __call_receiver_'
]
for (const fragment of requiredSource) {
	if (!source.includes(fragment)) {
		fail(`generated OCaml is missing the admitted class-carrier fragment: ${fragment}`)
	}
}
if (!/\(__place_receiver_\d+ : counter_t\)\.value <- __place_rhs_\d+/.test(source)) {
	fail('generated OCaml is missing the admitted nominal receiver field write')
}
const forbiddenSource = [
	'(Obj.magic self : counter_t).value',
	'(Obj.magic counter : counter_t).value',
	'(Obj.magic (!counter) : counter_t).value',
	'counter := Obj.magic',
	'counter_bump (Obj.magic counter)',
	'counter_bump (Obj.magic (makeCounter ()))'
]
for (const fragment of forbiddenSource) {
	if (source.includes(fragment)) {
		fail(`generated OCaml reintroduced an unsafe cast at an admitted class-carrier boundary: ${fragment}`)
	}
}
NODE

first_report="$(mktemp)"
inspection_report="$(mktemp)"
invalid_inspection_log="$(mktemp)"
invalid_output="out-invalid-monomorphic-class-$$"
invalid_captured_storage_log="$(mktemp)"
invalid_captured_storage_output="out-invalid-captured-class-storage-$$"
invalid_receiver_log="$(mktemp)"
invalid_receiver_output="out-invalid-monomorphic-receiver-$$"
invalid_call_receiver_log="$(mktemp)"
invalid_call_receiver_output="out-invalid-call-receiver-$$"
invalid_call_schedule_log="$(mktemp)"
invalid_call_schedule_output="out-invalid-call-schedule-$$"
invalid_constructor_result_log="$(mktemp)"
invalid_constructor_result_output="out-invalid-constructor-result-$$"
missing_constructor_boundary_log="$(mktemp)"
missing_constructor_boundary_output="out-missing-constructor-boundary-$$"
invalid_constructor_identity_log="$(mktemp)"
invalid_constructor_identity_output="out-invalid-constructor-identity-$$"
trap 'rm -f "$first_report" "$inspection_report" "$invalid_inspection_log" "$invalid_captured_storage_log" "$invalid_receiver_log" "$invalid_call_receiver_log" "$invalid_call_schedule_log" "$invalid_constructor_result_log" "$missing_constructor_boundary_log" "$invalid_constructor_identity_log"; rm -rf "$invalid_output" "$invalid_captured_storage_output" "$invalid_receiver_output" "$invalid_call_receiver_output" "$invalid_call_schedule_output" "$invalid_constructor_result_output" "$missing_constructor_boundary_output" "$invalid_constructor_identity_output"' EXIT

cp "$report_file" "$first_report"
haxe build.hxml -D ocaml_build=native
if ! cmp -s "$first_report" "$report_file"; then
	echo "The monomorphic-class representation report changed across identical compiler runs" >&2
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
const decision = report.representation?.decisions?.find(item =>
	item.id === 'representation:Counter:internal-value')
const capturedDecision = report.representation?.decisions?.find(item =>
	item.id === 'representation:Counter:captured-local-storage')
if (!report.summary?.valid
	|| decision?.nominalTargetModuleName !== 'Main'
	|| decision?.nominalTargetTypeName !== 'counter_t'
	|| !/^sha256:[0-9a-f]{64}$/.test(decision?.nominalLayoutRevision ?? '')
	|| capturedDecision?.storageMutationPolicy !== 'shared-local-cell'
	|| capturedDecision?.nominalLayoutRevision !== decision?.nominalLayoutRevision) {
	throw new Error('reflaxe.ocaml inspection did not preserve the sealed Counter carrier and captured cell')
}
NODE

cp -R out "$invalid_output"
node - "$invalid_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const decision = report.representations?.find(item =>
	item.id === 'representation:Counter:internal-value')
if (decision == null) {
	throw new Error('missing Counter representation to corrupt')
}
decision.nominalTargetTypeName = 'wrong_counter_t'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
if (
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output "$invalid_output" --require-lowering --json
) >"$invalid_inspection_log" 2>&1; then
	echo "The external inspector accepted a nominal class carrier with a corrupted target type" >&2
	exit 1
fi
if ! grep -Fq "does not match its sealed nominal carrier layout" "$invalid_inspection_log"; then
	echo "The external inspector rejected the corrupted nominal carrier for an unexpected reason" >&2
	cat "$invalid_inspection_log" >&2
	exit 1
fi

cp -R out "$invalid_captured_storage_output"
node - "$invalid_captured_storage_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const decision = report.representations?.find(item =>
	item.id === 'representation:Counter:captured-local-storage')
if (decision == null) {
	throw new Error('missing captured Counter representation to corrupt')
}
decision.storageMutationPolicy = 'immutable-binding'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
if (
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output "$invalid_captured_storage_output" --require-lowering --json
) >"$invalid_captured_storage_log" 2>&1; then
	echo "The external inspector accepted a captured nominal class carrier without shared-cell ownership" >&2
	exit 1
fi
if ! grep -Fq "selects immutable-binding storage for nominal carrier domain captured-local-storage, expected shared-local-cell" "$invalid_captured_storage_log"; then
	echo "The external inspector rejected the corrupted captured nominal storage policy for an unexpected reason" >&2
	cat "$invalid_captured_storage_log" >&2
	exit 1
fi

cp -R out "$invalid_receiver_output"
node - "$invalid_receiver_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const plan = report.plans?.find(item =>
	item.place?.receiverRepresentationId === 'representation:Counter:internal-value')
if (plan == null) {
	throw new Error('missing admitted Counter receiver to corrupt')
}
plan.place.receiverRepresentationId = 'representation:Counter:corrupted'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
if (
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output "$invalid_receiver_output" --require-lowering --json
) >"$invalid_receiver_log" 2>&1; then
	echo "The external inspector accepted a field plan with a missing nominal receiver decision" >&2
	exit 1
fi
if ! grep -Fq 'refers to missing receiver representation \"representation:Counter:corrupted\"' "$invalid_receiver_log"; then
	echo "The external inspector rejected the corrupted nominal receiver for an unexpected reason" >&2
	cat "$invalid_receiver_log" >&2
	exit 1
fi

cp -R out "$invalid_call_receiver_output"
node - "$invalid_call_receiver_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const call = report.calls?.find(item => item.kind === 'direct-instance-haxe-method')
if (call?.receiver == null) {
	throw new Error('missing admitted instance receiver to corrupt')
}
call.receiver.inputSemanticTypeId = 'Int'
call.receiver.inputCarrierTypeId = 'int'
call.receiver.inputRepresentationId = 'representation:Int:internal-value'
call.receiver.outputSemanticTypeId = 'Int'
call.receiver.outputCarrierTypeId = 'int'
call.receiver.outputRepresentationId = 'representation:Int:internal-value'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
if (
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output "$invalid_call_receiver_output" --require-lowering --json
) >"$invalid_call_receiver_log" 2>&1; then
	echo "The external inspector accepted a call with a corrupted nominal receiver" >&2
	exit 1
fi
if ! grep -Fq 'instance receiver outside the sealed nominal carrier family' "$invalid_call_receiver_log"; then
	echo "The external inspector rejected the corrupted call receiver for an unexpected reason" >&2
	cat "$invalid_call_receiver_log" >&2
	exit 1
fi

cp -R out "$invalid_call_schedule_output"
node - "$invalid_call_schedule_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const call = report.calls?.find(item => item.kind === 'direct-instance-haxe-method')
if (call?.evaluationSchedule?.length !== 3) {
	throw new Error('missing admitted instance schedule to corrupt')
}
const receiver = call.evaluationSchedule[0]
call.evaluationSchedule[0] = call.evaluationSchedule[1]
call.evaluationSchedule[1] = receiver
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
if (
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output "$invalid_call_schedule_output" --require-lowering --json
) >"$invalid_call_schedule_log" 2>&1; then
	echo "The external inspector accepted arguments evaluated before the instance receiver" >&2
	exit 1
fi
if ! grep -Fq 'has an invalid receiver materialization' "$invalid_call_schedule_log"; then
	echo "The external inspector rejected the reordered instance schedule for an unexpected reason" >&2
	cat "$invalid_call_schedule_log" >&2
	exit 1
fi

cp -R out "$invalid_constructor_result_output"
node - "$invalid_constructor_result_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const call = report.calls?.find(item => item.kind === 'direct-haxe-constructor')
if (call?.result == null) {
	throw new Error('missing admitted constructor result to corrupt')
}
for (const side of ['input', 'output']) {
	call.result[`${side}SemanticTypeId`] = 'Int'
	call.result[`${side}CarrierTypeId`] = 'int'
	call.result[`${side}RepresentationId`] = 'representation:Int:internal-value'
}
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
if (
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output "$invalid_constructor_result_output" --require-lowering --json
) >"$invalid_constructor_result_log" 2>&1; then
	echo "The external inspector accepted a constructor with a primitive result" >&2
	exit 1
fi
if ! grep -Fq 'has no sealed nominal constructor result' "$invalid_constructor_result_log"; then
	echo "The external inspector rejected the corrupted constructor result for an unexpected reason" >&2
	cat "$invalid_constructor_result_log" >&2
	exit 1
fi

cp -R out "$missing_constructor_boundary_output"
node - "$missing_constructor_boundary_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const boundaryIndex = report.callableBoundaries?.findIndex(item =>
	item.kind === 'direct-haxe-constructor')
if (boundaryIndex == null || boundaryIndex < 0) {
	throw new Error('missing constructor boundary to remove')
}
report.callableBoundaries.splice(boundaryIndex, 1)
report.callableBoundaryCount -= 1
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
if (
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output "$missing_constructor_boundary_output" --require-lowering --json
) >"$missing_constructor_boundary_log" 2>&1; then
	echo "The external inspector accepted constructor calls without their definition boundary" >&2
	exit 1
fi
if ! grep -Fq 'refers to missing callable boundary' "$missing_constructor_boundary_log"; then
	echo "The external inspector rejected the missing constructor boundary for an unexpected reason" >&2
	cat "$missing_constructor_boundary_log" >&2
	exit 1
fi

cp -R out "$invalid_constructor_identity_output"
node - "$invalid_constructor_identity_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const boundary = report.callableBoundaries?.find(item =>
	item.kind === 'direct-haxe-constructor')
if (boundary == null) {
	throw new Error('missing constructor boundary identity to corrupt')
}
boundary.sourceFieldName = 'create'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
if (
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output "$invalid_constructor_identity_output" --require-lowering --json
) >"$invalid_constructor_identity_log" 2>&1; then
	echo "The external inspector accepted a constructor boundary with the wrong source field" >&2
	exit 1
fi
if ! grep -Fq 'identifies constructor field \"create\" instead of \"new\"' "$invalid_constructor_identity_log"; then
	echo "The external inspector rejected the corrupted constructor identity for an unexpected reason" >&2
	cat "$invalid_constructor_identity_log" >&2
	exit 1
fi

echo "MONOMORPHIC_CLASS_CARRIER:PASS"
