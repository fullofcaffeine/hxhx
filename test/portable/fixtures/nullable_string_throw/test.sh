#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
inspection="$(mktemp)"
oracle="$(mktemp)"
trap 'rm -f "$inspection" "$oracle"' EXIT

"$HAXE_BIN" -cp src --run Main >"$oracle"
diff -u expected.stdout "$oracle"
"$HAXE_BIN" -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$inspection"

node - "$inspection" <<'NODE'
const fs = require('fs')
const inspection = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
const runtime = JSON.parse(fs.readFileSync('out/ocaml_runtime_requirement_report.json', 'utf8'))
const throws = report.controls.filter(item => item.kind === 'throw' && item.functionId.startsWith('Main|Main|'))
if (!inspection.summary.valid || throws.length !== 4) {
	throw new Error('Nullable-string throw plans did not survive public inspection')
}
for (const decision of throws) {
	const payload = decision.payload
	if (payload?.inputSemanticTypeId !== 'String'
		|| payload.inputCarrierTypeId !== 'string'
		|| payload.inputRepresentationId !== 'representation:String:internal-value'
		|| payload.outputSemanticTypeId !== payload.inputSemanticTypeId
		|| payload.outputCarrierTypeId !== payload.inputCarrierTypeId
		|| payload.outputRepresentationId !== payload.inputRepresentationId
		|| payload.conversion !== 'repr-and-recover-exact-value'
		|| decision.runtimeTags.join(',') !== 'Dynamic'
		|| decision.runtimeTagPolicy !== 'merge-dynamic-with-exact-runtime-value'
		|| decision.proofId !== 'exact-value-throw-control-v1') {
		throw new Error('Nullable-string throw lost its sentinel-preserving value and tag policy')
	}
	if (!runtime.requirements.some(item => item.id === `${decision.id}:runtime:${decision.runtimeCapabilityId}`)) {
		throw new Error('Nullable-string throw lost its exact runtime requirement owner')
	}
	const inspected = inspection.lowering.controls.find(item => item.id === decision.id)
	if (inspected?.payload?.conversion !== payload.conversion) {
		throw new Error('Public inspection changed the nullable-string conversion')
	}
}
NODE

echo "NULLABLE_STRING_THROW:PASS"
