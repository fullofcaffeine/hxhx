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
const boundary = report.functionResultBoundaries.find(entry => entry.source === 'nested-nullable-enum-callable')
const controls = report.controls.filter(entry => entry.functionId === boundary?.functionId && entry.kind === 'return')

if (report.functionResultBoundaryModel !== 'typed-ocaml-function-result-boundary-v5'
	|| boundary?.result?.inputSemanticTypeId !== 'Choice'
	|| boundary.result.inputCarrierTypeId !== 'haxe-enum-native-variant-carrier-v1:Choice'
	|| boundary.result.outputSemanticTypeId !== 'Null<Choice>'
	|| boundary.result.outputCarrierTypeId !== 'Obj.t'
	|| boundary.result.conversion !== 'box-exact-enum-to-nullable-enum'
	|| boundary.nullableEnum?.semanticTypeId !== 'Choice'
	|| boundary.proofId !== 'nested-nullable-enum-function-result-v1'
	|| controls.length !== 2
	|| !controls.some(entry => entry.payload?.conversion === 'preserve-nullable-carrier')
	|| !controls.some(entry => entry.payload?.conversion === 'box-exact-enum-to-nullable-carrier')) {
	throw new Error('the nested helper did not seal its null, enum-local, and normal enum result paths')
}
const start = source.indexOf('let wrap =')
const end = source.indexOf('\n\nlet describe =', start)
const body = source.slice(start, end)
if (start < 0
	|| end < 0
	|| !body.includes('let choose = fun () -> (try Obj.repr ((')
	|| !body.includes('HxRuntime.Hx_return (HxRuntime.hx_null)')
	|| !body.includes('HxRuntime.Hx_return (Obj.repr value)')
	|| !body.includes('| HxRuntime.Hx_return __ret_')
	|| !body.includes(': Obj.t) in Wrapped')
	|| body.includes('Obj.magic (HxRuntime.hx_null)')) {
	throw new Error('generated choose did not convert each nullable-enum result exactly once')
}
NODE

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$INSPECTION_COPY"

node - "$INSPECTION_COPY" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const boundary = report.lowering.functionResultBoundaries.find(entry => entry.source === 'nested-nullable-enum-callable')
if (report.summary.valid !== true
	|| boundary?.result?.conversion !== 'box-exact-enum-to-nullable-enum'
	|| boundary.nullableEnum?.semanticTypeId !== 'Choice') {
	throw new Error('public inspection lost the nested nullable-enum result proof')
}
NODE

for mutation in enum-name source-kind callable-id carrier missing-proof reordered; do
	invalid_output="$INVALID_ROOT/$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const boundary = report.functionResultBoundaries.find(entry => entry.source === 'nested-nullable-enum-callable')
if (boundary?.nullableEnum == null)
	throw new Error('missing nested nullable-enum boundary to corrupt')
switch (mutation) {
	case 'enum-name':
		boundary.nullableEnum.semanticTypeId = 'OtherChoice'
		break
	case 'source-kind':
		boundary.source = 'callable-boundary'
		break
	case 'callable-id':
		boundary.callableBoundaryId = 'nested-callable-boundary:000000000000000000000000'
		break
	case 'carrier':
		boundary.result.outputCarrierTypeId = 'Choice'
		break
	case 'missing-proof':
		boundary.nullableEnum = null
		break
	case 'reordered':
		report.functionResultBoundaries.reverse()
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
		echo "The public inspector accepted corrupted nested nullable-enum $mutation evidence" >&2
		exit 1
	fi
	if ! grep -Eiq 'function-result|function result|representation' "$invalid_log"; then
		echo "The public inspector rejected nested nullable-enum $mutation evidence for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

echo "NESTED_NULLABLE_ENUM_RESULT:PASS"
