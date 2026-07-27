#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
REPORT_COPY="$(mktemp)"
INSPECTION_COPY="$(mktemp)"
TAMPER_INSPECTION="$(mktemp)"
trap 'rm -f "$REPORT_COPY" "$INSPECTION_COPY" "$TAMPER_INSPECTION"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
	echo "Missing generated exact-throw source or lowering report" >&2
	exit 1
fi

node - "$SOURCE_FILE" "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const sha256 = /^sha256:[0-9a-f]{64}$/
const rawSha256 = /^[0-9a-f]{64}$/
const bodyRevision = /^[0-9]+:[0-9a-f]{64}$/

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 36
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v12'
	|| report.controlCount !== report.controls.length
	|| !sha256.test(report.controlRevision)) {
	fail('unexpected exact-throw control report schema, model, inventory, or revision')
}

const throws = report.controls.filter(control =>
	control.kind === 'throw' && control.functionId.startsWith('Main|Main|'))
if (throws.length !== 9) {
	fail(`expected 9 represented throw decisions, got ${throws.length}`)
}
const expectedByFunction = new Map([
	['throwInt', 1],
	['throwBool', 1],
	['throwString', 1],
	['throwNullString', 1],
	['throwNullableInt', 1],
	['throwNullableBool', 1],
	['rethrowInt', 2],
	['rethrowNullableInt', 1]
])
for (const [name, expectedCount] of expectedByFunction) {
	const decisions = throws.filter(control =>
		control.functionId.includes(`|function|${name}|`))
	if (decisions.length !== expectedCount) {
		fail(`expected ${expectedCount} sealed ${name} throw decisions, got ${decisions.length}`)
	}
}
if (throws.some(control => control.functionId.includes('|function|mixedThrow|'))) {
	fail('the mixed Int/Float function partially published an unsafe throw family')
}

const expectedCarrier = new Map([
	['Int', 'int'],
	['Bool', 'bool'],
	['String', 'string'],
	['Null<Int>', 'Obj.t'],
	['Null<Bool>', 'Obj.t']
])
const expectedConversion = new Map([
	['Int', 'repr-and-recover-exact-value'],
	['Bool', 'box-bool-and-recover-exact-value'],
	['String', 'repr-and-recover-exact-value'],
	['Null<Int>', 'preserve-nullable-int-throw-carrier'],
	['Null<Bool>', 'normalize-nullable-bool-throw-carrier']
])
const expectedProof = new Map([
	['Int', 'exact-value-throw-control-v1'],
	['Bool', 'exact-value-throw-control-v1'],
	['String', 'exact-value-throw-control-v1'],
	['Null<Int>', 'nullable-int-throw-control-v1'],
	['Null<Bool>', 'nullable-bool-throw-control-v1']
])
const ids = new Set()
for (const control of throws) {
	const payload = control.payload
	const carrier = payload == null ? null : expectedCarrier.get(payload.inputSemanticTypeId)
	if (ids.has(control.id)
		|| control.effect !== 'raise-haxe-value'
		|| control.targetKind !== 'haxe-exception-channel'
		|| control.targetId !== 'control-target:haxe-exception-channel:v1'
		|| control.runtimeTags.join(',') !== 'Dynamic'
		|| control.runtimeTagPolicy !== 'merge-dynamic-with-exact-runtime-value'
		|| control.mechanism !== 'runtime-typed-haxe-exception-signal'
		|| control.runtimeCapabilityId !== 'hxhx-runtime:typed-haxe-exception-signal-v1'
		|| control.profileEligibility.join(',') !== 'metal,portable'
		|| control.proofId !== expectedProof.get(payload.inputSemanticTypeId)
		|| !control.reason
		|| !control.proofClaim
		|| !control.source.file
		|| control.source.min < 0
		|| control.source.max < control.source.min
		|| !rawSha256.test(control.programRevision)
		|| !bodyRevision.test(control.bodyRevision)
		|| control.pipelineRevision !== 'ocaml-function-plans-v38'
		|| !carrier
		|| payload.inputCarrierTypeId !== carrier
		|| payload.inputRepresentationId !== `representation:${payload.inputSemanticTypeId}:internal-value`
		|| payload.signalCarrierTypeId !== 'Obj.t'
		|| payload.outputSemanticTypeId !== payload.inputSemanticTypeId
		|| payload.outputCarrierTypeId !== carrier
		|| payload.outputRepresentationId !== payload.inputRepresentationId
		|| payload.conversion !== expectedConversion.get(payload.inputSemanticTypeId)
		|| payload.proofId !== expectedProof.get(payload.inputSemanticTypeId)
		|| !payload.proofClaim) {
		fail(`throw decision ${control.id} has an incomplete exact-value exception crossing`)
	}
	ids.add(control.id)
}

function functionBody(name, nextName) {
	const start = source.indexOf(`let ${name} =`)
	const end = source.indexOf(`\nlet ${nextName} =`, start)
	if (start < 0 || end < 0)
		fail(`generated source is missing function boundary ${name} -> ${nextName}`)
	return source.slice(start, end)
}

const intBody = functionBody('throwInt', 'throwBool')
if (!intBody.includes('hx_throw_typed_rtti (Obj.repr 123) ["Dynamic"]')
	|| intBody.includes('["Dynamic"; "Int"]')) {
	fail('exact Int throw syntax did not consume its sealed runtime-value tag policy')
}
const boolBody = functionBody('throwBool', 'throwString')
if (!boolBody.includes('hx_throw_typed_rtti (HxRuntime.box_bool true) ["Dynamic"]')
	|| boolBody.includes('["Dynamic"; "Bool"]')) {
	fail('exact Bool throw syntax did not consume its sealed boxing and tag policy')
}
const stringBody = functionBody('throwString', 'throwNullString')
if (!stringBody.includes('hx_throw_typed_rtti (Obj.repr "boom") ["Dynamic"]')
	|| stringBody.includes('["Dynamic"; "String"]')) {
	fail('exact String throw syntax did not defer the String tag to the runtime value')
}
const nullStringBody = functionBody('throwNullString', 'throwNullableInt')
if (!nullStringBody.includes('HxString.hx_null_string')
	|| !nullStringBody.includes('hx_throw_typed_rtti (Obj.repr value) ["Dynamic"]')
	|| nullStringBody.includes('["Dynamic"; "String"]')) {
	fail('null String throw syntax could incorrectly force a String catch')
}
const nullableIntBody = functionBody('throwNullableInt', 'throwNullableBool')
if (!nullableIntBody.includes('hx_throw_typed_rtti value ["Dynamic"]')
	|| nullableIntBody.includes('Obj.repr value')
	|| nullableIntBody.includes('Obj.magic')) {
	fail('exact Null<Int> throw did not preserve its existing carrier')
}
const nullableBoolBody = functionBody('throwNullableBool', 'rethrowInt')
if ((nullableBoolBody.match(/HxRuntime\.is_null __throw_nullable_bool_/g) || []).length !== 1
	|| (nullableBoolBody.match(/HxRuntime\.box_bool \(HxRuntime\.unbox_bool_or_obj __throw_nullable_bool_/g) || []).length !== 1
	|| nullableBoolBody.includes('Obj.magic')
	|| nullableBoolBody.includes('["Dynamic"; "Bool"]')
	|| nullableBoolBody.includes('["Dynamic"; "Int"]')) {
	fail('exact Null<Bool> throw did not normalize its non-null exception payload once')
}
const rethrowBody = functionBody('rethrowInt', 'rethrowNullableInt')
if ((rethrowBody.match(/hx_throw_typed_rtti/g) || []).length < 2
	|| rethrowBody.includes('["Dynamic"; "Int"]')) {
	fail('exact Int rethrow did not use its sealed exception-channel decisions')
}
const nullableRethrowBody = functionBody('rethrowNullableInt', 'mixedThrow')
if (!nullableRethrowBody.includes('hx_throw_typed_rtti nullable ["Dynamic"]')
	|| nullableRethrowBody.includes('hx_throw_typed_rtti (Obj.repr nullable)')
	|| nullableRethrowBody.includes('Obj.magic')) {
	fail('nullable Int rethrow did not preserve the sealed nullable carrier')
}
const mixedBody = functionBody('mixedThrow', 'catchInt')
if (!mixedBody.includes('["Dynamic"; "Int"]')
	|| !mixedBody.includes('["Dynamic"; "Float"]')) {
	fail('the mixed supported/unsupported function did not remain wholly on the legacy throw path')
}
NODE

cp "$REPORT_FILE" "$REPORT_COPY"
haxe build.hxml
if ! cmp -s "$REPORT_COPY" "$REPORT_FILE"; then
	echo "The exact same typed program produced a different throw-control report" >&2
	diff -u "$REPORT_COPY" "$REPORT_FILE" >&2 || true
	exit 1
fi

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$INSPECTION_COPY"

node - "$INSPECTION_COPY" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const throws = report.lowering.controls.filter(control =>
	control.kind === 'throw' && control.functionId.startsWith('Main|Main|'))
if (report.schemaVersion !== 21
	|| report.summary.valid !== true
	|| report.summary.controlCount !== report.lowering.controls.length
	|| throws.length !== 9
	|| throws.some(control =>
		control.runtimeTags.join(',') !== 'Dynamic'
		|| control.runtimeTagPolicy !== 'merge-dynamic-with-exact-runtime-value')
	|| report.lowering.scope !== 'typed-place-call-and-function-loop-throw-catch-control-families') {
	throw new Error('public inspection did not expose the 9 validated represented throw decisions')
}
NODE

node - "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const transfer = report.controls.find(control =>
	control.kind === 'throw' && control.functionId.includes('|function|throwNullableBool|'))
if (!transfer)
	throw new Error('missing nullable Bool throw to corrupt')
transfer.payload.conversion = 'preserve-nullable-int-throw-carrier'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$TAMPER_INSPECTION" 2>&1; then
	echo "Public inspection accepted a throw with a corrupt runtime tag policy" >&2
	exit 1
fi
if ! grep -q "invalid represented Haxe exception crossing" "$TAMPER_INSPECTION"; then
	echo "Public inspection rejected the corrupt throw without the expected actionable reason" >&2
	cat "$TAMPER_INSPECTION" >&2
	exit 1
fi
cp "$REPORT_COPY" "$REPORT_FILE"

echo "REFLAXE_OCAML_EXACT_THROW_CONTROL_FIXTURE:PASS transfers=9"
