#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (report.schemaVersion !== 83
	|| report.iMapInterfaceModel !== 'typed-imap-interface-adapter-v6'
	|| report.iMapStorageAliasCount !== 0
	|| report.iMapStorageAliases?.length !== 0) {
	throw new Error('an ordinary source IMap local was mistaken for a closed standard Map storage alias')
}

const conversions = report.iMapInterfaceConversions
if (conversions.length !== 6
	|| conversions.length !== report.iMapInterfaceConversionCount
	|| conversions.some(conversion => conversion.sourceKind !== 'standard-string-map-abstract'
		|| conversion.sourceSemanticTypeId !== 'Map<String, Int>'
		|| conversion.targetSemanticTypeId !== 'haxe.IMap<String, Int>'
		|| conversion.targetCarrierTypeId !== 'Obj.t(haxe_Constraints.imap_t)')) {
	throw new Error('the rejected storage-alias cases did not use the ordinary checked IMap adapter')
}

for (const functionName of ['returned', 'captured', 'assigned', 'compared', 'passed']) {
	if (!conversions.some(conversion => conversion.functionId.includes(`|function|${functionName}|`)))
		throw new Error(`the ${functionName} case has no ordinary Map-to-IMap conversion`)
}
const assignedConversions = conversions.filter(conversion => conversion.functionId.includes('|function|assigned|'))
if (assignedConversions.length !== 2
	|| !assignedConversions.some(conversion => conversion.role === 'local-initializer')
	|| !assignedConversions.some(conversion => conversion.role === 'assignment')) {
	throw new Error('the reassigned IMap local did not keep checked adapters for both standard Map values')
}

const generated = fs.readFileSync('out/Main.ml', 'utf8')
if (!generated.includes('__adapt_standard_imap_'))
	throw new Error('generated OCaml did not build the checked standard IMap adapter')
NODE

repo_root="$(cd ../../../.. && pwd)"
fixture_root="$PWD"
inspection_report="$(mktemp)"
trap 'rm -f "$inspection_report"' EXIT
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
if (report.schemaVersion !== 46
	|| !report.summary?.valid
	|| report.summary.iMapStorageAliasCount !== 0
	|| report.summary.iMapInterfaceConversionCount !== 6) {
	throw new Error('inspection did not preserve the ordinary IMap conversion boundary')
}
NODE

echo "IMAP_STORAGE_ALIAS_NEGATIVE:PASS"
