#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
INSPECTION_COPY="$(mktemp)"
INVALID_RESULT_ROOT="$(mktemp -d)"
trap 'rm -f "$INSPECTION_COPY"; rm -rf "$INVALID_RESULT_ROOT"' EXIT

# The upstream routes establish the observable virtual dispatch and early-return
# behavior. The native build performed by the portable harness is checked below
# for the narrower compiler claim: each concrete method owns only its completed
# result—an OCaml string or the absence of a value—and does not gain a direct
# receiver, dispatch, or call contract.
bash ../../../../scripts/reflaxe-ocaml/run-inheritance-override-oracle.sh

node - out/Main.ml out/haxe_Exception.ml out/sys_io_Stdio.ml out/ocaml_lowering_report.json <<'NODE'
const fs = require('fs')
const mainSource = fs.readFileSync(process.argv[2], 'utf8')
const exceptionSource = fs.readFileSync(process.argv[3], 'utf8')
const stdioSource = fs.readFileSync(process.argv[4], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[5], 'utf8'))

const expected = [
	{token: '|Base|instance|function|label|', source: mainSource, generatedName: 'base_label__impl'},
	{token: '|Child|instance|function|label|', source: mainSource, generatedName: 'child_label__impl'},
	{token: 'Exception|Exception|instance|function|details|', source: exceptionSource, generatedName: 'details__impl'}
]
const stringResults = report.functionResultBoundaries.filter(boundary =>
	boundary.source === 'non-generic-instance-exact-string-declaration')
if (report.schemaVersion !== 79 || stringResults.length !== expected.length) {
	throw new Error(`expected ${expected.length} declaration-only instance String results, got ${stringResults.length}`)
}

for (const item of expected) {
	const admission = report.controlAdmissions.find(entry => entry.functionId.includes(item.token))
	const returns = admission?.families?.find(entry => entry.family === 'return')
	const result = report.functionResultBoundaries.find(entry => entry.functionId === admission?.functionId)
	if (returns?.status !== 'admitted'
		|| returns.occurrenceCount !== 1
		|| returns.decisionCount !== 1
		|| result?.source !== 'non-generic-instance-exact-string-declaration'
		|| result.callableBoundaryId != null
		|| result.resultKind !== 'value'
		|| result.result?.inputSemanticTypeId !== 'String'
		|| result.result?.inputCarrierTypeId !== 'string'
		|| result.result?.inputRepresentationId !== 'representation:String:internal-value'
		|| result.result?.outputSemanticTypeId !== 'String'
		|| result.result?.outputCarrierTypeId !== 'string'
		|| result.result?.outputRepresentationId !== 'representation:String:internal-value'
		|| result.result?.conversion !== 'identity'
		|| result.proofId !== 'non-generic-instance-exact-string-function-result-v1'
		|| report.callableBoundaries.some(boundary => boundary.functionId === admission.functionId)) {
		throw new Error(`${item.token} did not receive a result-only exact-String boundary`)
	}

	const start = item.source.indexOf(`let ${item.generatedName} =`)
	const end = item.source.indexOf('\nlet ', start + 1)
	const body = item.source.slice(start, end)
	if (start < 0
		|| end < 0
		|| !body.includes('HxRuntime.Hx_return')
		|| body.includes('__fallback_result')
		|| body.includes('Obj.magic __fallback_result')) {
		throw new Error(`${item.generatedName} still uses legacy result recovery`)
	}
}

const expectedVoid = [
	{token: '|Base|instance|function|visit|', source: mainSource, generatedName: 'base_visit__impl'},
	{token: '|Child|instance|function|visit|', source: mainSource, generatedName: 'child_visit__impl'},
	{token: 'Stdio|OcamlStdioOutput|instance|function|writeString|', source: stdioSource, generatedName: 'ocamlstdiooutput_writeString__impl'}
]
const voidResults = report.functionResultBoundaries.filter(boundary =>
	boundary.source === 'non-generic-instance-effect-only-void-declaration')
if (voidResults.length !== expectedVoid.length) {
	throw new Error(`expected ${expectedVoid.length} declaration-only instance Void results, got ${voidResults.length}`)
}
for (const item of expectedVoid) {
	const admission = report.controlAdmissions.find(entry => entry.functionId.includes(item.token))
	const returns = admission?.families?.find(entry => entry.family === 'return')
	const result = report.functionResultBoundaries.find(entry => entry.functionId === admission?.functionId)
	if (returns?.status !== 'admitted'
		|| returns.occurrenceCount !== 1
		|| returns.decisionCount !== 1
		|| result?.source !== 'non-generic-instance-effect-only-void-declaration'
		|| result.callableBoundaryId != null
		|| result.resultKind !== 'effect-only-void'
		|| result.result != null
		|| result.proofId !== 'non-generic-instance-effect-only-void-function-result-v1'
		|| report.callableBoundaries.some(boundary => boundary.functionId === admission.functionId)) {
		throw new Error(`${item.token} did not receive a result-only payloadless boundary`)
	}

	const start = item.source.indexOf(`let ${item.generatedName} =`)
	const end = item.source.indexOf('\nlet ', start + 1)
	const body = item.source.slice(start, end)
	if (start < 0
		|| end < 0
		|| !body.includes('raise (HxRuntime.Hx_return_void)')
		|| !body.includes('| HxRuntime.Hx_return_void -> ()')
		|| body.includes('Hx_return (Obj.repr ())')) {
		throw new Error(`${item.generatedName} did not mechanically consume its payloadless return boundary`)
	}
}
NODE

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$INSPECTION_COPY"
node - "$INSPECTION_COPY" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const stringResults = report.lowering.functionResultBoundaries.filter(boundary =>
	boundary.source === 'non-generic-instance-exact-string-declaration')
const voidResults = report.lowering.functionResultBoundaries.filter(boundary =>
	boundary.source === 'non-generic-instance-effect-only-void-declaration')
if (report.schemaVersion !== 45
	|| report.summary.valid !== true
	|| stringResults.length !== 3
	|| voidResults.length !== 3
	|| stringResults.some(boundary =>
		boundary.callableBoundaryId != null
		|| boundary.result?.inputSemanticTypeId !== 'String'
		|| boundary.result?.inputCarrierTypeId !== 'string'
		|| boundary.result?.outputRepresentationId !== 'representation:String:internal-value')
	|| voidResults.some(boundary =>
		boundary.callableBoundaryId != null
		|| boundary.resultKind !== 'effect-only-void'
		|| boundary.result != null)) {
	throw new Error('public inspection did not preserve the declaration-only instance String and Void results')
}
NODE

for mutation in int-source carrier callable-owner; do
	invalid_output="$INVALID_RESULT_ROOT/$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const boundary = report.functionResultBoundaries.find(entry =>
	entry.functionId.includes('|Child|instance|function|label|'))
if (boundary?.source !== 'non-generic-instance-exact-string-declaration') {
	throw new Error('missing child String result boundary to corrupt')
}
switch (mutation) {
	case 'int-source':
		boundary.source = 'non-generic-instance-exact-int-declaration'
		boundary.proofId = 'non-generic-instance-exact-int-function-result-v1'
		break
	case 'carrier':
		boundary.result.outputCarrierTypeId = 'int'
		break
	case 'callable-owner':
		boundary.source = 'callable-boundary'
		boundary.callableBoundaryId = 'callable-boundary:missing'
		boundary.proofId = 'callable-function-result-boundary-v1'
		break
	default:
		throw new Error(`unsupported mutation ${mutation}`)
}
report.functionResultBoundaryRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify(report.functionResultBoundaries)).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
	invalid_log="$INVALID_RESULT_ROOT/$mutation.log"
	if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
		echo "The public inspector accepted corrupted instance String result $mutation evidence" >&2
		exit 1
	fi
	if ! grep -Eiq 'function-result|function result' "$invalid_log"; then
		echo "The public inspector rejected corrupted instance String result $mutation evidence for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

for mutation in wrong-source value-carrier callable-owner; do
	invalid_output="$INVALID_RESULT_ROOT/void-$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const boundary = report.functionResultBoundaries.find(entry =>
	entry.functionId.includes('|Child|instance|function|visit|'))
if (boundary?.source !== 'non-generic-instance-effect-only-void-declaration') {
	throw new Error('missing child Void result boundary to corrupt')
}
switch (mutation) {
	case 'wrong-source':
		boundary.source = 'non-generic-instance-exact-string-declaration'
		boundary.proofId = 'non-generic-instance-exact-string-function-result-v1'
		break
	case 'value-carrier': {
		const stringBoundary = report.functionResultBoundaries.find(entry =>
			entry.source === 'non-generic-instance-exact-string-declaration')
		if (stringBoundary?.result == null)
			throw new Error('missing exact String carrier used to construct the invalid Void record')
		boundary.resultKind = 'value'
		boundary.result = stringBoundary.result
		break
	}
	case 'callable-owner':
		boundary.source = 'callable-boundary'
		boundary.callableBoundaryId = 'callable-boundary:missing'
		boundary.proofId = 'callable-function-result-boundary-v1'
		break
	default:
		throw new Error(`unsupported mutation ${mutation}`)
}
report.functionResultBoundaryRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify(report.functionResultBoundaries)).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
	invalid_log="$INVALID_RESULT_ROOT/void-$mutation.log"
	if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
		echo "The public inspector accepted corrupted instance Void result $mutation evidence" >&2
		exit 1
	fi
	if ! grep -Eiq 'function-result|function result' "$invalid_log"; then
		echo "The public inspector rejected corrupted instance Void result $mutation evidence for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

echo "INHERITANCE_RESULT_BOUNDARY:PASS string=3 void=3"
