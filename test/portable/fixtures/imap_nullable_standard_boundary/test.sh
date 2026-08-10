#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (report.schemaVersion !== 77
	|| report.iMapInterfaceModel !== 'typed-imap-interface-adapter-v6'
	|| report.iMapInterfaceConversionCount !== 0
	|| report.iMapInterfaceCallCount !== 0
	|| report.iMapStorageAliasCount !== 4) {
	throw new Error('nullable standard Maps did not use the current closed storage-alias contract')
}

const expected = new Map([
	['string', {count: 2, source: 'Null<Map<String, Int>>', key: 'String', value: 'Int', carrier: 'HxMap.string_map', operation: 'get_string'}],
	['int', {count: 1, source: 'Null<Map<Int, String>>', key: 'Int', value: 'String', carrier: 'HxMap.int_map', operation: 'get_int'}],
	['object-identity', {count: 1, source: 'Null<Map<_Main.ObjectKey, Int>>', key: '_Main.ObjectKey', value: 'Int', carrier: 'HxMap.obj_map', operation: 'get_object'}]
])
for (const [kind, facts] of expected) {
	const aliases = report.iMapStorageAliases.filter(alias => alias.standardKeyKind === kind)
	if (aliases.length !== facts.count
		|| aliases.some(alias => alias.sourceSemanticTypeId !== facts.source
			|| alias.sourceCarrierTypeId !== 'Obj.t'
			|| alias.preservedCarrierTypeId !== facts.carrier
			|| alias.targetSemanticTypeId !== `haxe.IMap<${facts.key}, ${facts.value}>`
		|| alias.nullPolicy !== 'check-null-and-unbox'
		|| alias.proofId !== 'typed-standard-map-storage-alias-v2'
		|| alias.runtimeRequirementIds?.join(',') !== `${alias.id}:runtime:haxe-runtime-core`
		|| alias.pipelineRevision !== 'ocaml-function-plans-v92'
		|| alias.runtimeUseOccurrences?.length !== 2
		|| alias.runtimeUseOccurrences[0].exactSymbol !== 'HxRuntime.is_null'
		|| alias.runtimeUseOccurrences[0].role !== 'check-null'
		|| alias.runtimeUseOccurrences[1].exactSymbol !== 'HxRuntime.hx_throw_typed'
		|| alias.runtimeUseOccurrences[1].role !== 'throw-null-access'
		|| alias.uses.length !== 1
		|| alias.uses[0].carrierTypeId !== facts.carrier
		|| alias.uses[0].nativeOperation !== facts.operation)) {
		throw new Error(`the ${kind} nullable Map boundary lacks its exact source, carrier, null, or use proof`)
	}
}
for (const alias of report.iMapStorageAliases) {
	const requirements = report.runtimeRequirements.filter(requirement => requirement.decisionId === alias.id)
	if (requirements.length !== 1
		|| requirements[0].id !== `${alias.id}:runtime:haxe-runtime-core`
		|| requirements[0].rootModules?.join(',') !== 'HxRuntime') {
		throw new Error(`nullable storage alias ${alias.id} lacks its exact HxRuntime requirement`)
	}
}

const generated = fs.readFileSync('out/Main.ml', 'utf8')
const nullChecks = generated.match(/HxRuntime\.is_null __nullable_standard_map_/g) || []
const checkedRecoveries = generated.match(/else Obj\.obj __nullable_standard_map_/g) || []
if (nullChecks.length !== 4
	|| checkedRecoveries.length !== 4
	|| !generated.includes('HxRuntime.hx_throw_typed (Obj.repr "Null Access") ["String"; "Dynamic"]')
	|| generated.includes('Obj.magic __nullable_standard_map_')
	|| generated.includes('__adapt_standard_imap_')) {
	throw new Error('generated OCaml did not evaluate, check, and recover each nullable Map exactly once')
}
NODE

repo_root="$(cd ../../../.. && pwd)"
fixture_root="$PWD"
inspection_report="$(mktemp)"
lowering_backup="$(mktemp)"
cp out/ocaml_lowering_report.json "$lowering_backup"
trap 'cp "$lowering_backup" out/ocaml_lowering_report.json; rm -f "$inspection_report" "$lowering_backup"' EXIT

inspect() {
	(
		cd "$repo_root"
		haxe -cp packages/reflaxe.ocaml/src \
			--macro 'nullSafety("reflaxe.ocaml")' \
			--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
			inspect --project "$fixture_root" --output out --require-lowering --json
	)
}

inspect >"$inspection_report"
node - "$inspection_report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (report.schemaVersion !== 45
	|| !report.summary?.valid
	|| report.summary.iMapStorageAliasCount !== 4) {
	throw new Error('inspection did not preserve the nullable standard Map decisions')
}
NODE

corrupt_alias() {
	local field="$1"
	local value="$2"
	cp "$lowering_backup" out/ocaml_lowering_report.json
	node - "$field" "$value" <<'NODE'
const fs = require('fs')
const crypto = require('crypto')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
report.iMapStorageAliases[0][process.argv[2]] = process.argv[3]
report.iMapInterfaceRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify({
	conversions: report.iMapInterfaceConversions,
	calls: report.iMapInterfaceCalls,
	storageAliases: report.iMapStorageAliases
})).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
}

corrupt_alias sourceCarrierTypeId HxMap.obj_map
if inspect >"$inspection_report" 2>/dev/null; then
	echo "inspection accepted a nullable Map alias with the wrong source carrier" >&2
	exit 1
fi

corrupt_alias nullPolicy non-null-source
if inspect >"$inspection_report" 2>/dev/null; then
	echo "inspection accepted a nullable Map alias with the wrong null policy" >&2
	exit 1
fi

echo "NULLABLE_STANDARD_IMAP_BOUNDARY:PASS"
