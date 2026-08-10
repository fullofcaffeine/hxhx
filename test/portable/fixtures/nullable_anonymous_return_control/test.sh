#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
CALL_STACK_SOURCE="out/haxe_CallStack.ml"
NATIVE_STACK_SOURCE="out/haxe_NativeStackTrace.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-ocaml-nullable-anonymous-return.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$CALL_STACK_SOURCE" ] || [ ! -f "$NATIVE_STACK_SOURCE" ] || [ ! -f "$REPORT_FILE" ]; then
	echo "Missing generated nullable-anonymous source or lowering report" >&2
	exit 1
fi

"$ROOT/scripts/reflaxe-ocaml/run-nullable-anonymous-return-oracle.sh"

node - "$SOURCE_FILE" "$CALL_STACK_SOURCE" "$NATIVE_STACK_SOURCE" "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const mainSource = fs.readFileSync(process.argv[2], 'utf8')
const callStackSource = fs.readFileSync(process.argv[3], 'utf8')
const nativeStackSource = fs.readFileSync(process.argv[4], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[5], 'utf8'))

function fail(message) {
	throw new Error(message)
}

const expectedFunctions = [
	'Main|Main|static|function|choose|generics:0|required:String,required:Bool->Null<_Main.Location>',
	'haxe.CallStack|CallStack_Impl_|static|function|parseFileLine|generics:0|required:String->Null<{ line : Int, file : String }>',
	'haxe.NativeStackTrace|NativeStackTrace|static|function|parseFileLine|generics:0|required:String->Null<{ line : Int, file : String }>'
]
// This reviewed identifier is the first 24 hexadecimal characters of SHA-256
// over "ocaml-anonymous-structure-v4\nanonymous{file:String,line:Int}". The
// model revision is part of the public report identity, so an intentional model
// change must update this expectation and review the whole proof chain below.
const expectedStructureId = 'anonymous-structure:f7e4f011fbcb9b3678770b4a'
const boundaries = (report.functionResultBoundaries ?? []).filter(boundary =>
	boundary.source === 'static-nullable-anonymous-declaration')
if (boundaries.length !== expectedFunctions.length)
	fail(`expected ${expectedFunctions.length} nullable anonymous result boundaries, got ${boundaries.length}`)
for (const functionId of expectedFunctions) {
	const boundary = boundaries.find(item => item.functionId === functionId)
	if (!boundary)
		fail(`missing nullable anonymous result boundary for ${functionId}`)
	const proof = boundary.anonymousStructure
	if (boundary.callableBoundaryId !== null
		|| boundary.proofId !== 'static-nullable-anonymous-function-result-v1'
		|| boundary.result?.conversion !== 'identity'
		|| boundary.result?.inputCarrierTypeId !== 'Obj.t'
		|| boundary.result?.outputCarrierTypeId !== 'Obj.t'
		|| proof?.semanticTypeId !== 'anonymous{file:String,line:Int}'
		|| proof.structureId !== expectedStructureId
		|| proof.representationId !== 'representation:anonymous{file:String,line:Int}:internal-value'
		|| !/^sha256:[0-9a-f]{64}$/.test(proof.structureRevision)
		|| !/^sha256:[0-9a-f]{64}$/.test(proof.representationRevision)) {
		fail(`nullable anonymous result boundary lacks its exact structure/representation proof: ${functionId}`)
	}
}

for (const functionId of expectedFunctions) {
	const admission = (report.controlAdmissions ?? []).find(item => item.functionId === functionId)
	const returns = admission?.families?.find(family => family.family === 'return')
	const expectedReturns = functionId.includes('|function|choose|') ? 1 : 4
	if (returns?.status !== 'admitted'
		|| returns.occurrenceCount !== expectedReturns
		|| returns.decisionCount !== expectedReturns
		|| returns.blockers.length !== 0) {
		fail(`nullable anonymous returns remain blocked for ${functionId}`)
	}
	if ((report.callableBoundaries ?? []).some(boundary => boundary.functionId === functionId))
		fail(`result-only nullable anonymous function gained callable ownership: ${functionId}`)
	const decisions = (report.controls ?? []).filter(control =>
		control.functionId === functionId && control.kind === 'return')
	for (const decision of decisions) {
		if (decision.payload?.conversion !== 'preserve-anonymous-carrier'
			|| decision.payload?.proofId !== 'exact-anonymous-carrier-early-return-control-v1'
			|| decision.payload?.representationRevision !== boundaries.find(item => item.functionId === functionId)?.anonymousStructure?.representationRevision
			|| decision.proofId !== 'exact-anonymous-carrier-early-return-control-v1') {
			fail(`nullable anonymous return did not reuse its function-owned carrier: ${decision.id}`)
		}
	}
}

for (const [label, source] of [
	['choose', mainSource],
	['CallStack.parseFileLine', callStackSource],
	['NativeStackTrace.parseFileLine', nativeStackSource]
]) {
	if (!source.includes('raise (HxRuntime.Hx_return (HxRuntime.hx_null))')
		|| !source.includes('| HxRuntime.Hx_return __ret_')
		|| source.includes('Hx_return (Obj.repr (HxRuntime.hx_null))')
		|| source.includes('Hx_return (Obj.magic (HxRuntime.hx_null))')) {
		fail(`${label} did not preserve the nullable anonymous carrier through the private return signal`)
	}
}
NODE

# Rebuilding the same typed program must reproduce the exact semantic report and
# the three generated functions. This checks the claim-bearing files rather than
# Dune's intentionally mutable external build cache.
cp "$REPORT_FILE" "$TMP_ROOT/report.before.json"
cp "$SOURCE_FILE" "$TMP_ROOT/Main.before.ml"
cp "$CALL_STACK_SOURCE" "$TMP_ROOT/CallStack.before.ml"
cp "$NATIVE_STACK_SOURCE" "$TMP_ROOT/NativeStackTrace.before.ml"
haxe build.hxml
cmp "$TMP_ROOT/report.before.json" "$REPORT_FILE"
cmp "$TMP_ROOT/Main.before.ml" "$SOURCE_FILE"
cmp "$TMP_ROOT/CallStack.before.ml" "$CALL_STACK_SOURCE"
cmp "$TMP_ROOT/NativeStackTrace.before.ml" "$NATIVE_STACK_SOURCE"

# The public inspector is a second reader of the generated proof. It does not
# share request-local typed expressions with the compiler, so a pass here shows
# that another tool can verify the structure/result/control ownership chain.
VALID_INSPECTION="$TMP_ROOT/valid-inspection.json"
haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$VALID_INSPECTION"
node - "$VALID_INSPECTION" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (report.schemaVersion !== 45
	|| report.summary?.valid !== true
	|| report.lowering?.status !== 'present'
	|| report.lowering?.schemaVersion !== 70) {
	throw new Error('public inspection did not validate the nullable anonymous return report')
}
const boundaries = report.lowering.functionResultBoundaries.filter(item =>
	item.source === 'static-nullable-anonymous-declaration')
const controls = report.lowering.controls.filter(item =>
	item.kind === 'return' && item.payload?.conversion === 'preserve-anonymous-carrier')
if (boundaries.length !== 3 || controls.length !== 9)
	throw new Error(`public inspection exposed ${boundaries.length} boundaries and ${controls.length} controls; expected 3 and 9`)
NODE

# Each mutation keeps the surrounding JSON well-formed and refreshes the local
# inventory digest. The inspector must therefore reject the semantic lie itself,
# not merely notice malformed JSON or a stale aggregate hash.
for mutation in wrong-shape stale-structure wrong-representation fake-callable value-boxing unplanned-return-expression; do
	invalid_output="$TMP_ROOT/$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const functionId = 'Main|Main|static|function|choose|generics:0|required:String,required:Bool->Null<_Main.Location>'
const boundary = report.functionResultBoundaries.find(item => item.functionId === functionId)
const control = report.controls.find(item => item.functionId === functionId && item.kind === 'return')
if (!boundary || !control)
	throw new Error('missing Main.choose nullable anonymous proof to corrupt')

switch (mutation) {
	case 'wrong-shape':
		boundary.anonymousStructure.semanticTypeId = 'anonymous{file:String}'
		break
	case 'stale-structure':
		boundary.anonymousStructure.structureRevision = `sha256:${'0'.repeat(64)}`
		break
	case 'wrong-representation':
		boundary.anonymousStructure.representationId = 'representation:String:internal-value'
		break
	case 'fake-callable':
		boundary.callableBoundaryId = report.callableBoundaries[0]?.id ?? 'callable-boundary:missing'
		break
	case 'value-boxing':
		control.payload.conversion = 'box-and-recover-exact-value'
		control.payload.proofId = 'exact-value-early-return-control-v2'
		control.proofId = 'exact-value-early-return-control-v2'
		break
	case 'unplanned-return-expression':
		control.payload.proofId = 'unplanned-return-expression-v1'
		control.proofId = 'unplanned-return-expression-v1'
		break
	default:
		throw new Error(`unsupported corruption ${mutation}`)
}

report.functionResultBoundaryRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify(report.functionResultBoundaries)).digest('hex')}`
report.controlRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify({
	targets: report.controlTargets,
	decisions: report.controls,
	catchChains: report.controlCatches
})).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
	invalid_log="$TMP_ROOT/$mutation.log"
	if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
		echo "Public inspection accepted corrupted nullable anonymous return evidence: $mutation" >&2
		exit 1
	fi
	if ! grep -Eiq 'anonymous-object|function-result|function result' "$invalid_log"; then
		echo "Public inspection rejected $mutation for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

echo "NULLABLE_ANONYMOUS_RETURN_CONTROL:PASS functions=3 returns=9 corruptions=6"
