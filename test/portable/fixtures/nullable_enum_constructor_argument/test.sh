#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
INSPECTION_COPY="$(mktemp)"
INVALID_ROOT="$(mktemp -d)"
INSPECTOR_DIR="$(mktemp -d)"
trap 'rm -f "$INSPECTION_COPY"; rm -rf "$INVALID_ROOT" "$INSPECTOR_DIR"' EXIT

node - out/Main.ml out/ocaml_lowering_report.json <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const boundary = report.functionResultBoundaries.find(entry => entry.functionId.includes('|Main|static|function|rebuild|'))

if (report.functionResultBoundaryModel !== 'typed-ocaml-function-result-boundary-v6'
	|| boundary?.source !== 'non-generic-static-nullable-enum-declaration'
	|| boundary.callableBoundaryId != null
	|| boundary.result?.inputSemanticTypeId !== 'haxe.macro.FixtureChoice'
	|| boundary.result?.inputCarrierTypeId !== 'fixturechoice'
	|| boundary.result?.outputSemanticTypeId !== 'Null<haxe.macro.FixtureChoice>'
	|| boundary.result?.outputCarrierTypeId !== 'Obj.t'
	|| boundary.result?.conversion !== 'box-exact-enum-to-nullable-enum'
	|| boundary.nullableEnum?.semanticTypeId !== 'haxe.macro.FixtureChoice'
	|| boundary.nullableEnum.carrierTypeId !== 'fixturechoice'
	|| boundary.result.nullableEnumCarrier?.descriptor?.targetModuleName !== 'Haxe_macro_FixtureChoice'
	|| boundary.result.nullableEnumCarrier?.descriptor?.targetTypeName !== 'fixturechoice'
	|| boundary.result.nullableEnumCarrier?.descriptor?.revision !== boundary.nullableEnum.descriptor?.revision
	|| boundary.proofId !== 'non-generic-static-nullable-enum-function-result-v1'
	|| report.callableBoundaries.some(entry => entry.functionId === boundary.functionId)) {
	throw new Error('rebuild did not receive the narrow static nullable-enum result boundary')
}
const start = source.indexOf('let rebuild =')
const end = source.indexOf('\n\nlet wrap =', start)
const body = source.slice(start, end)
if (start < 0
	|| end < 0
	|| !body.includes('try Obj.repr ((')
	|| !body.includes('rebuildValue')
	|| !body.includes(': Obj.t)')) {
	throw new Error('generated rebuild did not box its exact normal result once')
}
const wrap = source.match(/let wrap = fun \(present : bool\) -> \(let (__enum_arg_\d+) = (.+) in Haxe_macro_FixtureEnvelope\.Wrapped \(Stdlib\.Sys\.opaque_identity \1\) : Haxe_macro_FixtureEnvelope\.fixtureenvelope\)/)
if (wrap?.[2] !== 'Obj.obj (HxEnum.unbox_or_obj "haxe.macro.FixtureChoice" (rebuild (Obj.obj (HxEnum.unbox_or_obj "haxe.macro.FixtureChoice" (choose present)))))')
	throw new Error('generated constructor did not consume the nullable result carrier')
NODE

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	-D reflaxe_runtime -main reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	--neko "$INSPECTOR_DIR/inspect.n"
neko "$INSPECTOR_DIR/inspect.n" \
	inspect --project "$PWD" --output out --require-lowering --json >"$INSPECTION_COPY"

node - "$INSPECTION_COPY" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const boundary = report.lowering.functionResultBoundaries.find(entry => entry.functionId.includes('|Main|static|function|rebuild|'))
if (report.summary.valid !== true
	|| boundary?.source !== 'non-generic-static-nullable-enum-declaration'
	|| boundary.result?.conversion !== 'box-exact-enum-to-nullable-enum'
	|| boundary.nullableEnum?.semanticTypeId !== 'haxe.macro.FixtureChoice') {
	throw new Error('public inspection lost the static nullable-enum function-result proof')
}
NODE

for mutation in enum-name source-kind carrier missing-proof; do
	invalid_output="$INVALID_ROOT/$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const crypto = require('crypto')
const reportJson = require('../../../../scripts/ci/ocaml-report-json')
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const boundary = report.functionResultBoundaries.find(entry => entry.functionId.includes('|Main|static|function|rebuild|'))
if (boundary?.nullableEnum == null)
	throw new Error('missing static nullable-enum boundary to corrupt')
switch (mutation) {
	case 'enum-name':
		boundary.nullableEnum.semanticTypeId = 'haxe.macro.OtherChoice'
		break
	case 'source-kind':
		boundary.source = 'non-generic-instance-nullable-enum-declaration'
		break
	case 'carrier':
		boundary.result.outputCarrierTypeId = 'haxe.macro.FixtureChoice'
		break
	case 'missing-proof':
		boundary.nullableEnum = null
		break
	default:
		throw new Error(`unsupported mutation ${mutation}`)
}
report.functionResultBoundaryRevision = `sha256:${crypto.createHash('sha256').update(reportJson(report.functionResultBoundaries)).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
	invalid_log="$INVALID_ROOT/$mutation.log"
	if neko "$INSPECTOR_DIR/inspect.n" \
		inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
		echo "The public inspector accepted corrupted static nullable-enum $mutation evidence" >&2
		exit 1
	fi
	if ! grep -Eiq 'function-result|function result|representation' "$invalid_log"; then
		echo "The public inspector rejected static nullable-enum $mutation evidence for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

echo "NULLABLE_ENUM_CONSTRUCTOR_ARGUMENT:PASS"
