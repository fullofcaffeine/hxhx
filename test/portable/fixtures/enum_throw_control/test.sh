#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
RUNTIME_REPORT_FILE="out/ocaml_runtime_requirement_report.json"
EXECUTABLE="out/_build/default/out.exe"
FIRST_REPORT="$(mktemp)"
ACTUAL_STDOUT="$(mktemp)"
INSPECTION_REPORT="$(mktemp)"
INVALID_LOG="$(mktemp)"
INVALID_OUTPUT="out-invalid-enum-throw-$$"
trap 'rm -f "$FIRST_REPORT" "$ACTUAL_STDOUT" "$INSPECTION_REPORT" "$INVALID_LOG"; rm -rf "$INVALID_OUTPUT"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ] || [ ! -f "$RUNTIME_REPORT_FILE" ] || [ ! -x "$EXECUTABLE" ]; then
	echo "Missing generated enum throw source, lowering/runtime report, or executable" >&2
	exit 1
fi

"$EXECUTABLE" >"$ACTUAL_STDOUT"
diff -u expected.stdout "$ACTUAL_STDOUT"

node - "$SOURCE_FILE" "$REPORT_FILE" "$RUNTIME_REPORT_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const runtime = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'))

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 52
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v15') {
	fail('unexpected enum throw report schema or control model')
}

const sourceFile = 'external-source/src/Main.hx'
const controls = report.controls.filter(item =>
	item.kind === 'throw'
	&& item.source?.file === sourceFile
	&& item.payload?.inputSemanticTypeId === 'Signal')
const expectedFunctions = ['throwIdle', 'throwPair', 'throwPayload']
if (controls.length !== expectedFunctions.length) {
	fail(`expected ${expectedFunctions.length} direct Signal throw decisions, got ${controls.length}`)
}
for (const functionName of expectedFunctions) {
	const control = controls.find(item => item.functionId.includes(`|function|${functionName}|`))
	const payload = control?.payload
	if (control == null
		|| control.pipelineRevision !== 'ocaml-function-plans-v65'
		|| control.proofId !== 'exact-enum-constructor-throw-control-v1'
		|| control.runtimeTags.join(',') !== 'Dynamic,Signal'
		|| control.runtimeTagPolicy !== 'merge-dynamic-with-exact-runtime-value'
		|| payload?.inputSemanticTypeId !== 'Signal'
		|| payload.inputCarrierTypeId !== 'haxe-enum-native-variant-carrier-v1:Signal'
		|| payload.inputRepresentationId !== 'control-representation:enum-direct-v1:Signal'
		|| payload.signalCarrierTypeId !== 'Obj.t'
		|| payload.outputSemanticTypeId !== payload.inputSemanticTypeId
		|| payload.outputCarrierTypeId !== payload.inputCarrierTypeId
		|| payload.outputRepresentationId !== payload.inputRepresentationId
		|| payload.conversion !== 'box-enum-throw-carrier'
		|| payload.nominalRepresentation != null
		|| payload.proofId !== control.proofId) {
		fail(`${functionName} did not retain the exact direct-enum throw carrier`)
	}
}

const plannedBoxes = source.match(/HxEnum\.box_if_needed "Signal" \(Obj\.repr /g) ?? []
if (plannedBoxes.length !== 3
	|| !source.includes('Obj.repr Idle')
	|| !source.includes('Obj.repr (Payload ')
	|| !source.includes('Obj.repr (Pair ')
	|| !source.includes('["Dynamic"; "Signal"]')
	|| !source.includes('HxEnum.unbox_or_obj "Signal"')) {
	fail('generated OCaml did not mechanically apply the three sealed enum throw decisions')
}

const sourceRequirements = report.runtimeRequirements.filter(item =>
	item.source?.file === sourceFile
	&& item.subject?.id === 'Signal'
	&& item.semanticCapability === 'haxe-enum-dynamic-box')
if (sourceRequirements.length !== 3
	|| sourceRequirements.some(item =>
		item.sourceId !== item.decisionId
		|| item.rootModules.join(',') !== 'HxEnum'
		|| !controls.some(control => control.id === item.decisionId))) {
	fail('the lowering report did not bind every source Signal throw to one checked HxEnum requirement')
}

const runtimeRequirements = runtime.requirements.filter(item =>
	item.source?.file === sourceFile
	&& item.subject?.id === 'Signal'
	&& item.semanticCapability === 'haxe-enum-dynamic-box')
if (runtime.authorityStatus !== 'partial'
	|| runtimeRequirements.length !== 3
	|| !runtime.requirementRootModules.includes('HxEnum')) {
	fail('the runtime report lost the exact Signal reasons or overstated its authority')
}
NODE

cp "$REPORT_FILE" "$FIRST_REPORT"
haxe build.hxml
if ! cmp -s "$FIRST_REPORT" "$REPORT_FILE"; then
	echo "The same typed program produced a different enum throw report" >&2
	diff -u "$FIRST_REPORT" "$REPORT_FILE" >&2 || true
	exit 1
fi

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$INSPECTION_REPORT"

node - "$INSPECTION_REPORT" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const sourceFile = 'external-source/src/Main.hx'
const controls = report.lowering.controls.filter(item =>
	item.sourceFile === sourceFile
	&& item.payload?.conversion === 'box-enum-throw-carrier')
if (report.schemaVersion !== 31
	|| report.summary.valid !== true
	|| controls.length !== 3
	|| controls.some(item =>
		item.payload?.inputCarrierTypeId !== 'haxe-enum-native-variant-carrier-v1:Signal'
		|| item.runtimeTags.join(',') !== 'Dynamic,Signal')) {
	throw new Error('public inspection did not validate the direct enum throw decisions')
}
NODE

expect_invalid() {
	local mutation="$1"
	local expected="$2"
	rm -rf "$INVALID_OUTPUT"
	cp -R out "$INVALID_OUTPUT"
node - "$INVALID_OUTPUT/ocaml_lowering_report.json" "$mutation" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const control = report.controls.find(item =>
	item.payload?.conversion === 'box-enum-throw-carrier'
	&& item.payload?.inputSemanticTypeId === 'Signal')
if (control?.payload == null)
	throw new Error('missing direct enum throw payload to corrupt')
switch (mutation) {
	case 'carrier':
		control.payload.inputCarrierTypeId = 'haxe-enum-native-variant-carrier-v1:OtherSignal'
		break
	case 'tags':
		control.runtimeTags = ['Dynamic']
		break
	case 'proof':
		control.proofId = 'exact-value-throw-control-v2'
		control.payload.proofId = control.proofId
		break
	case 'source':
		control.source.min += 1
		control.source.max += 1
		const sourceRequirement = report.runtimeRequirements.find(item => item.decisionId === control.id)
		if (sourceRequirement == null)
			throw new Error('missing direct enum throw runtime requirement to corrupt')
		sourceRequirement.source.min = control.source.min
		sourceRequirement.source.max = control.source.max
		break
	case 'function':
		control.functionId += ':forged'
		break
	case 'enum':
		const previousEnum = control.payload.inputSemanticTypeId
		const forgedEnum = 'OtherSignal'
		control.payload.inputSemanticTypeId = forgedEnum
		control.payload.outputSemanticTypeId = forgedEnum
		control.payload.inputCarrierTypeId = `haxe-enum-native-variant-carrier-v1:${forgedEnum}`
		control.payload.outputCarrierTypeId = control.payload.inputCarrierTypeId
		control.payload.inputRepresentationId = `control-representation:enum-direct-v1:${forgedEnum}`
		control.payload.outputRepresentationId = control.payload.inputRepresentationId
		control.runtimeTags = ['Dynamic', forgedEnum]
		const enumRequirement = report.runtimeRequirements.find(item => item.decisionId === control.id)
		if (enumRequirement == null || enumRequirement.subject?.id !== previousEnum)
			throw new Error('missing direct enum throw enum requirement to corrupt')
		enumRequirement.subject.id = forgedEnum
		break
	case 'revision':
		control.pipelineRevision = 'ocaml-function-plans-v60'
		break
	case 'runtime':
		const requirementId = `${control.id}:runtime:haxe-enum-dynamic-box`
		report.runtimeRequirements = report.runtimeRequirements.filter(item => item.id !== requirementId)
		report.runtimeRequirementCount = report.runtimeRequirements.length
		break
	default:
		throw new Error(`unknown mutation ${mutation}`)
}
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
	if [[ "$mutation" == "source" || "$mutation" == "function" || "$mutation" == "enum" ]]; then
		haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision \
			--preserve-control-revision "$INVALID_OUTPUT/ocaml_lowering_report.json"
	else
		haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision \
			"$INVALID_OUTPUT/ocaml_lowering_report.json"
	fi
	if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$PWD" --output "$INVALID_OUTPUT" --require-lowering --json \
		>"$INVALID_LOG" 2>&1; then
		echo "The inspector accepted a corrupted direct enum throw: $mutation" >&2
		exit 1
	fi
	if ! grep -Fq "$expected" "$INVALID_LOG"; then
		echo "The inspector rejected $mutation corruption for an unexpected reason" >&2
		cat "$INVALID_LOG" >&2
		exit 1
	fi
}

expect_invalid carrier "invalid direct enum-constructor exception carrier"
expect_invalid tags "invalid direct enum-constructor exception carrier"
expect_invalid proof "invalid direct enum-constructor exception carrier"
expect_invalid source "Control report revision does not match its targets, decisions, and catch chains"
expect_invalid function "Control report revision does not match its targets, decisions, and catch chains"
expect_invalid enum "Control report revision does not match its targets, decisions, and catch chains"
expect_invalid revision "uses unsupported function-plan pipeline"
expect_invalid runtime "refers to missing runtime requirement"

rm -rf "$INVALID_OUTPUT"
echo "ENUM_THROW_CONTROL:PASS throws=3 exact_catches=4 dynamic_fallback=1"
