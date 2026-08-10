#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
EXECUTABLE="out/_build/default/out.exe"
FIRST_REPORT="$(mktemp)"
ACTUAL_STDOUT="$(mktemp)"
INSPECTION_REPORT="$(mktemp)"
INVALID_LOG="$(mktemp)"
INVALID_OUTPUT="out-invalid-dynamic-throw-$$"
trap 'rm -f "$FIRST_REPORT" "$ACTUAL_STDOUT" "$INSPECTION_REPORT" "$INVALID_LOG"; rm -rf "$INVALID_OUTPUT"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ] || [ ! -x "$EXECUTABLE" ]; then
	echo "Missing generated Dynamic throw source, lowering report, or executable" >&2
	exit 1
fi

"$EXECUTABLE" >"$ACTUAL_STDOUT"
diff -u expected.stdout "$ACTUAL_STDOUT"

node - "$SOURCE_FILE" "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 79
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v23') {
	fail('unexpected Dynamic throw report schema or control model')
}

const controls = report.controls.filter(item =>
	item.kind === 'throw'
	&& item.payload?.inputSemanticTypeId === 'Dynamic')
if (controls.length !== 2) {
	fail(`expected two Dynamic throw decisions, got ${controls.length}`)
}
for (const control of controls) {
	const payload = control.payload
	if (control.pipelineRevision !== 'ocaml-function-plans-v95'
		|| control.proofId !== 'dynamic-carrier-throw-control-v1'
		|| control.runtimeTags.join(',') !== 'Dynamic'
		|| control.runtimeTagPolicy !== 'merge-dynamic-with-exact-runtime-value'
		|| payload?.inputCarrierTypeId !== 'Obj.t'
		|| payload.inputRepresentationId !== 'control-representation:Dynamic:runtime-obj-v1'
		|| payload.signalCarrierTypeId !== 'Obj.t'
		|| payload.outputSemanticTypeId !== 'Dynamic'
		|| payload.outputCarrierTypeId !== 'Obj.t'
		|| payload.outputRepresentationId !== payload.inputRepresentationId
		|| payload.conversion !== 'preserve-dynamic-throw-carrier'
		|| payload.nominalRepresentation != null
		|| payload.proofId !== control.proofId) {
		fail(`Dynamic throw ${control.id} does not preserve its control-only Obj.t carrier`)
	}
}

const dynamicCatches = report.controlCatches.flatMap(chain => chain.clauses)
	.filter(clause => clause.semanticTypeId === 'Dynamic')
if (dynamicCatches.length < 6
	|| dynamicCatches.some(clause =>
		clause.outputCarrierTypeId !== 'Obj.t'
		|| clause.outputRepresentationId !== 'control-representation:Dynamic:runtime-obj-v1'
		|| clause.matchPolicy !== 'match-all'
		|| clause.conversion !== 'preserve-dynamic-carrier')) {
	fail('the fixture did not preserve every final Dynamic catch carrier')
}

const dynamicCalls = report.calls.filter(call => call.calleeId === 'Main|Main::throwDynamic')
const expectedCrossings = [
	['Int', 'box-concrete-to-dynamic', 'dynamic-call-box-concrete-v1'],
	['Int', 'box-concrete-to-dynamic', 'dynamic-call-box-concrete-v1'],
	['Bool', 'box-exact-bool-to-dynamic', 'dynamic-call-box-bool-v1'],
	['String', 'box-concrete-to-dynamic', 'dynamic-call-box-concrete-v1'],
	['Dynamic', 'preserve-dynamic-carrier', 'dynamic-call-carrier-preserve-v1'],
	['Box', 'box-concrete-to-dynamic', 'dynamic-call-box-concrete-v1']
]
const actualCrossings = dynamicCalls.map(call => {
	const argument = call.arguments?.[0]
	return [argument?.inputSemanticTypeId, argument?.conversion, argument?.proofId]
}).sort((left, right) => left.join('|').localeCompare(right.join('|')))
expectedCrossings.sort((left, right) => left.join('|').localeCompare(right.join('|')))
if (JSON.stringify(actualCrossings) !== JSON.stringify(expectedCrossings)
	|| dynamicCalls.some(call =>
		call.pipelineRevision !== 'ocaml-function-plans-v95'
		|| call.arguments?.[0]?.outputSemanticTypeId !== 'Dynamic'
		|| call.arguments?.[0]?.outputCarrierTypeId !== 'Obj.t'
		|| call.arguments?.[0]?.outputRepresentationId !== 'representation:Dynamic:internal-value')) {
	fail(`typed call plans did not seal the complete concrete/Dynamic crossing matrix: ${JSON.stringify(actualCrossings)}`)
}

if (!/let throwDynamic = fun \(value : Obj\.t\) -> ignore \(HxType\.hx_throw_typed_rtti value \["Dynamic"\]\)/.test(source)
	|| !/let (__call_arg_0_\d+) = Obj\.repr 41 in throwDynamic \1/.test(source)
	|| !/let (__call_arg_0_\d+) = HxRuntime\.box_bool true in throwDynamic \1/.test(source)
	|| !/HxType\.hx_throw_typed_rtti caught \["Dynamic"\]/.test(source)
	|| source.includes('hx_throw_typed_rtti (Obj.repr value) ["Dynamic"]')
	|| source.includes('hx_throw_typed_rtti (Obj.repr caught) ["Dynamic"]')) {
	fail('generated OCaml did not mechanically preserve Dynamic throw carriers')
}
NODE

cp "$REPORT_FILE" "$FIRST_REPORT"
haxe build.hxml
if ! cmp -s "$FIRST_REPORT" "$REPORT_FILE"; then
	echo "The same typed program produced a different Dynamic throw-control report" >&2
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
const dynamicThrows = report.lowering.controls.filter(item =>
	item.payload?.inputSemanticTypeId === 'Dynamic')
if (report.schemaVersion !== 45
	|| report.summary.valid !== true
	|| dynamicThrows.length !== 2
	|| dynamicThrows.some(item =>
		item.payload?.conversion !== 'preserve-dynamic-throw-carrier'
		|| item.payload?.inputRepresentationId !== 'control-representation:Dynamic:runtime-obj-v1')) {
	throw new Error('public inspection did not validate the Dynamic throw decisions')
}
NODE

cp -R out "$INVALID_OUTPUT"
node - "$INVALID_OUTPUT/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const control = report.controls.find(item =>
	item.payload?.conversion === 'preserve-dynamic-throw-carrier')
if (control?.payload == null)
	throw new Error('missing Dynamic throw payload to corrupt')
control.payload.inputRepresentationId = 'representation:Dynamic:internal-value'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision \
	"$INVALID_OUTPUT/ocaml_lowering_report.json"
if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output "$INVALID_OUTPUT" --require-lowering --json \
	>"$INVALID_LOG" 2>&1; then
	echo "The inspector accepted a Dynamic throw with a false program representation" >&2
	exit 1
fi
if ! grep -Fq "invalid Dynamic exception carrier" "$INVALID_LOG"; then
	echo "The inspector rejected the corrupted Dynamic throw for an unexpected reason" >&2
	cat "$INVALID_LOG" >&2
	exit 1
fi

# Reset the copied output before changing a different owner. This case proves
# that the inspector checks the Bool argument requirement itself. A valid outer
# digest must not let a requirement select the wrong private runtime module.
rm -rf "$INVALID_OUTPUT"
cp -R out "$INVALID_OUTPUT"
node - "$INVALID_OUTPUT/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const requirement = report.runtimeRequirements.find(item =>
	item.semanticCapability === 'haxe-call-bool-carrier')
if (requirement == null)
	throw new Error('missing Bool-to-Dynamic call requirement to corrupt')
requirement.rootModules = ['HxArray']
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision \
	"$INVALID_OUTPUT/ocaml_lowering_report.json"
if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output "$INVALID_OUTPUT" --require-lowering --json \
	>"$INVALID_LOG" 2>&1; then
	echo "The inspector accepted a Bool-to-Dynamic call requirement with the wrong runtime module" >&2
	exit 1
fi
if ! grep -Fq "Boolean carrier requirement" "$INVALID_LOG"; then
	echo "The inspector rejected the corrupted Bool call requirement for an unexpected reason" >&2
	cat "$INVALID_LOG" >&2
	exit 1
fi

echo "DYNAMIC_THROW_CONTROL:PASS throws=2 runtime_values=5 null_dynamic_only=1"
