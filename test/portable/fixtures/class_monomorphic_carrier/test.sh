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

if (report.schemaVersion !== 25
	|| report.representationScope !== 'exact-int-bool-nullable-string-field-defaults-direct-simple-assignment-array-int-locals-monomorphic-class-v11') {
	fail('unexpected lowering-report schema or representation scope')
}

const decision = report.representations?.find(item =>
	item.id === 'representation:Counter:internal-value')
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

const admittedReceivers = (report.plans ?? []).filter(plan =>
	plan.place?.receiverSemanticTypeId === 'Counter'
	&& plan.place?.receiverRepresentationId === decision.id)
if (admittedReceivers.length !== 3
	|| admittedReceivers.some(plan =>
		plan.place.receiverCarrierTypeId !== 'counter_t'
		|| plan.place.kind !== 'instance-field')) {
	fail(`expected three Counter field plans to consume the sealed receiver, got ${admittedReceivers.length}`)
}

const instanceCalls = (report.calls ?? []).filter(call =>
	call.kind === 'direct-instance-haxe-method'
	&& call.sourceTypeName === 'Counter'
	&& call.sourceFieldName === 'bump')
const instanceBoundaries = (report.callableBoundaries ?? []).filter(boundary =>
	boundary.kind === 'direct-instance-haxe-method')
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

if (!source.includes('let counter = Obj.magic (counter_create 6)')
	|| !source.includes('(Obj.magic counter : counter_t).value')) {
	fail('the captured Counter local crossed the first-slice boundary instead of retaining the legacy path')
}

const requiredSource = [
	'type counter_t = { __hx_type : Obj.t; mutable value : int }',
	'let counter = counter_create (sourceValue ())',
	'(self : counter_t).value',
	'(counter : counter_t).value',
	'let __call_receiver_',
	'let __call_arg_0_',
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
invalid_receiver_log="$(mktemp)"
invalid_receiver_output="out-invalid-monomorphic-receiver-$$"
invalid_call_receiver_log="$(mktemp)"
invalid_call_receiver_output="out-invalid-call-receiver-$$"
invalid_call_schedule_log="$(mktemp)"
invalid_call_schedule_output="out-invalid-call-schedule-$$"
trap 'rm -f "$first_report" "$inspection_report" "$invalid_inspection_log" "$invalid_receiver_log" "$invalid_call_receiver_log" "$invalid_call_schedule_log"; rm -rf "$invalid_output" "$invalid_receiver_output" "$invalid_call_receiver_output" "$invalid_call_schedule_output"' EXIT

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
if (!report.summary?.valid
	|| decision?.nominalTargetModuleName !== 'Main'
	|| decision?.nominalTargetTypeName !== 'counter_t'
	|| !/^sha256:[0-9a-f]{64}$/.test(decision?.nominalLayoutRevision ?? '')) {
	throw new Error('reflaxe.ocaml inspection did not preserve the sealed Counter carrier')
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

echo "MONOMORPHIC_CLASS_CARRIER:PASS"
