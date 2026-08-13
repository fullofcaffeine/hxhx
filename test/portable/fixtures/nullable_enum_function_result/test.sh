#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
INSPECTION_COPY="$(mktemp)"
INVALID_ROOT="$(mktemp -d)"
trap 'rm -f "$INSPECTION_COPY"; rm -rf "$INVALID_ROOT"' EXIT

node - out/Main.ml out/ocaml_lowering_report.json <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const boundary = report.functionResultBoundaries.find(entry =>
	entry.functionId.includes('|Picker|instance|function|choose|'))
const admission = report.controlAdmissions.find(entry => entry.functionId === boundary?.functionId)
const returns = admission?.families?.find(entry => entry.family === 'return')
const earlyReturn = report.controls.find(entry => entry.functionId === boundary?.functionId && entry.kind === 'return')

if (report.functionResultBoundaryModel !== 'typed-ocaml-function-result-boundary-v3'
	|| boundary?.source !== 'non-generic-instance-nullable-enum-declaration'
	|| boundary.callableBoundaryId != null
	|| boundary.result?.inputSemanticTypeId !== 'Choice'
	|| boundary.result?.inputCarrierTypeId !== 'haxe-enum-native-variant-carrier-v1:Choice'
	|| boundary.result?.outputSemanticTypeId !== 'Null<Choice>'
	|| boundary.result?.outputCarrierTypeId !== 'Obj.t'
	|| boundary.result?.conversion !== 'box-exact-enum-to-nullable-enum'
	|| boundary.nullableEnum?.semanticTypeId !== 'Choice'
	|| boundary.proofId !== 'non-generic-instance-nullable-enum-function-result-v1'
	|| earlyReturn?.payload?.inputSemanticTypeId !== 'Choice'
	|| earlyReturn.payload.outputSemanticTypeId !== 'Null<Choice>'
	|| earlyReturn.payload.conversion !== 'box-exact-enum-to-nullable-carrier'
	|| earlyReturn.proofId !== 'exact-enum-to-nullable-early-return-control-v1'
	|| returns?.status !== 'admitted'
	|| returns.occurrenceCount !== 1
	|| report.callableBoundaries.some(entry => entry.functionId === boundary.functionId)) {
	throw new Error('choose did not receive the narrow nullable-enum result boundary')
}
const start = source.indexOf('let picker_choose =')
const end = source.indexOf('\n\n(* Generated', start)
const body = source.slice(start, end)
if (start < 0
	|| end < 0
	|| !body.includes('try Obj.repr ((')
	|| !body.includes('HxRuntime.Hx_return (Obj.repr (Payload 7))')
	|| !body.includes('Plain')
	|| !body.includes(': Obj.t)')) {
	throw new Error('generated choose did not box the completed early and normal result once')
}
NODE

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$INSPECTION_COPY"

node - "$INSPECTION_COPY" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const boundary = report.lowering.functionResultBoundaries.find(entry =>
	entry.functionId.includes('|Picker|instance|function|choose|'))
if (report.summary.valid !== true
	|| boundary?.source !== 'non-generic-instance-nullable-enum-declaration'
	|| boundary.result?.conversion !== 'box-exact-enum-to-nullable-enum'
	|| boundary.nullableEnum?.semanticTypeId !== 'Choice') {
	throw new Error('public inspection lost the nullable-enum function-result proof')
}
NODE

for mutation in enum-name carrier source-span missing-proof; do
	invalid_output="$INVALID_ROOT/$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const boundary = report.functionResultBoundaries.find(entry =>
	entry.functionId.includes('|Picker|instance|function|choose|'))
if (boundary?.nullableEnum == null)
	throw new Error('missing nullable-enum boundary to corrupt')
switch (mutation) {
	case 'enum-name':
		boundary.nullableEnum.semanticTypeId = 'OtherChoice'
		break
	case 'carrier':
		boundary.result.outputCarrierTypeId = 'choice'
		break
	case 'source-span':
		boundary.nullableEnum.source.max = boundary.nullableEnum.source.min - 1
		break
	case 'missing-proof':
		boundary.nullableEnum = null
		break
	default:
		throw new Error(`unsupported mutation ${mutation}`)
}
report.functionResultBoundaryRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify(report.functionResultBoundaries)).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
	invalid_log="$INVALID_ROOT/$mutation.log"
	if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
		echo "The public inspector accepted corrupted nullable-enum $mutation evidence" >&2
		exit 1
	fi
	if ! grep -Eiq 'function-result|function result|representation' "$invalid_log"; then
		echo "The public inspector rejected nullable-enum $mutation evidence for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

echo "NULLABLE_ENUM_FUNCTION_RESULT:PASS"
