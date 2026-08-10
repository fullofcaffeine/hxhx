#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (report.schemaVersion !== 73
	|| report.callModel !== 'typed-ocaml-directional-call-boundary-v22') {
	throw new Error('the IMap fixture did not produce the current sealed call-report schema')
}
if (report.iMapInterfaceModel !== 'typed-imap-interface-adapter-v6'
	|| report.iMapInterfaceConversionCount !== 5
	|| report.iMapInterfaceCallCount !== 55
	|| report.iMapStorageAliasCount !== 6
	|| report.calls?.some(call => call.kind === 'standard-imap-method')) {
	throw new Error('the IMap fixture did not hard-cut standard maps to the shared interface adapter')
}
const calls = report.iMapInterfaceCalls
if (calls.some(call =>
	call.pipelineRevision !== (call.functionId.includes('|nested-function|')
		? 'ocaml-nested-function-plans-v16'
		: 'ocaml-function-plans-v88')
	|| call.receiverCarrierTypeId !== 'Obj.t(haxe_Constraints.imap_t)'
	|| call.receiverSemanticTypeId !== `haxe.IMap<${call.keySemanticTypeId}, ${call.valueSemanticTypeId}>`)) {
	throw new Error('the IMap fixture did not seal all calls against the exact interface receiver')
}
const nestedCalls = calls.filter(call => call.functionId.includes('|nested-function|'))
if (nestedCalls.length !== 1
	|| nestedCalls[0].operation !== 'exists'
	|| nestedCalls[0].pipelineRevision !== 'ocaml-nested-function-plans-v16') {
	throw new Error('the nested function did not keep its exact IMap interface call plan')
}
const operations = new Set(calls.map(call => call.operation))
for (const operation of [
	'set',
	'get',
	'exists',
	'remove',
	'keys',
	'iterator',
	'key-value-iterator',
	'copy',
	'to-string',
	'clear'
]) {
	if (!operations.has(operation))
		throw new Error(`the IMap fixture did not cover ${operation}`)
}
const conversions = report.iMapInterfaceConversions
if (conversions.some(conversion => Object.hasOwn(conversion, 'roleIndex'))) {
	throw new Error('the IMap report still publishes request-local numeric role indices')
}
const localConversions = conversions.filter(conversion => conversion.role === 'local-initializer')
if (localConversions.length !== 2
	|| localConversions.some(conversion => !/^lexical-local-v1:[0-9a-f]{64}$/.test(conversion.roleIdentity))
	|| new Set(localConversions.map(conversion => conversion.roleIdentity)).size !== localConversions.length) {
	throw new Error('local IMap conversions did not use distinct stable lexical-local identities')
}
if (conversions.some(conversion => conversion.role === 'call-argument' && conversion.roleIdentity !== 'call-argument:0')) {
	throw new Error('call-argument IMap conversions did not preserve their stable named argument position')
}
const nestedConversions = conversions.filter(conversion => conversion.functionId.includes('|nested-function|'))
if (nestedConversions.length !== 1
	|| nestedConversions[0].role !== 'local-initializer'
	|| nestedConversions[0].sourceKind !== 'standard-string-map'
	|| nestedConversions[0].pipelineRevision !== 'ocaml-nested-function-plans-v16') {
	throw new Error('the nested function did not keep its exact concrete-to-IMap conversion plan')
}
const keyKinds = new Set(conversions.map(conversion => conversion.standardKeyKind))
if (![...['string', 'int', 'object-identity']].every(kind => keyKinds.has(kind))
	|| conversions.some(conversion =>
		conversion.sourceKind === 'user-implementation'
		|| conversion.methods.length !== 10
		|| conversion.targetCarrierTypeId !== 'Obj.t(haxe_Constraints.imap_t)')) {
	throw new Error('the IMap fixture did not preserve all three proven standard storage carriers')
}
const ordinaryAbstractConversion = conversions.find(conversion => conversion.sourceKind === 'standard-string-map-abstract')
if (!ordinaryAbstractConversion
	|| ordinaryAbstractConversion.sourceSemanticTypeId !== 'Map<String, Int>'
	|| ordinaryAbstractConversion.targetCarrierTypeId !== 'Obj.t(haxe_Constraints.imap_t)') {
	throw new Error('an ordinary source Map assigned to IMap did not keep the interface adapter')
}
const storageAliases = report.iMapStorageAliases
const expectedAliases = [
	{nested: false, kind: 'string', key: 'String', value: 'Int', carrier: 'HxMap.string_map', operation: 'set_string'},
	{nested: true, kind: 'string', key: 'String', value: 'Int', carrier: 'HxMap.string_map', operation: 'exists_string'},
	{nested: false, kind: 'int', key: 'Int', value: 'String', carrier: 'HxMap.int_map', operation: 'set_int'},
	{nested: true, kind: 'int', key: 'Int', value: 'String', carrier: 'HxMap.int_map', operation: 'exists_int'},
	{nested: false, kind: 'object-identity', key: '_Main.ObjectKey', value: 'Int', carrier: 'HxMap.obj_map', operation: 'set_object'},
	{nested: true, kind: 'object-identity', key: '_Main.ObjectKey', value: 'Int', carrier: 'HxMap.obj_map', operation: 'exists_object'}
]
for (const expected of expectedAliases) {
	const alias = storageAliases.find(candidate => candidate.functionId.includes('|nested-function|') === expected.nested
		&& candidate.standardKeyKind === expected.kind)
	const expectedPipeline = expected.nested ? 'ocaml-nested-function-plans-v16' : 'ocaml-function-plans-v88'
	if (!alias
		|| alias.sourceSemanticTypeId !== `Map<${expected.key}, ${expected.value}>`
		|| alias.targetSemanticTypeId !== `haxe.IMap<${expected.key}, ${expected.value}>`
		|| alias.sourceCarrierTypeId !== expected.carrier
		|| alias.preservedCarrierTypeId !== expected.carrier
		|| alias.nullPolicy !== 'non-null-source'
		|| alias.proofId !== 'typed-standard-map-storage-alias-v2'
		|| alias.runtimeRequirementIds?.length !== 0
		|| alias.runtimeUseOccurrences?.length !== 0
		|| report.runtimeRequirements.some(requirement => requirement.decisionId === alias.id)
		|| alias.pipelineRevision !== expectedPipeline
		|| alias.uses.length !== 1
		|| alias.uses[0].carrierTypeId !== expected.carrier
		|| alias.uses[0].nativeOperation !== expected.operation) {
		throw new Error(`the IMap fixture did not seal the ${expected.nested ? 'nested' : 'root'} ${expected.kind} Map storage alias`)
	}
}
for (const conversion of conversions) {
	const expectedRequirementIds = conversion.runtimeCapabilities.map(capability => `${conversion.id}:runtime:${capability}`)
	const actualRequirements = report.runtimeRequirements.filter(requirement => requirement.decisionId === conversion.id)
	if (actualRequirements.length !== expectedRequirementIds.length
		|| actualRequirements.some(requirement => !expectedRequirementIds.includes(requirement.id))) {
		throw new Error(`standard IMap conversion ${conversion.id} does not own its exact runtime requirements`)
	}
}
const formatted = conversions.filter(conversion => conversion.valueStringifier !== null)
if (formatted.length !== 5
	|| formatted.some(conversion =>
		!conversion.runtimeCapabilities.includes('haxe-array')
		|| (!conversion.runtimeCapabilities.includes('haxe-string-text')
			&& !conversion.runtimeCapabilities.includes('haxe-dynamic-text')))) {
	throw new Error('Map.toString was not sealed as typed pair traversal and entry formatting')
}
for (const conversion of formatted) {
	const textRole = conversion.keyStringifier === 'exact-string' || conversion.keyStringifier === 'dynamic-object'
		? 'format-key'
		: 'format-value'
	const expectedRoles = [
		'type-marker',
		'standard-map:get',
		'standard-map:set',
		'standard-map:exists',
		'standard-map:remove',
		'wrap-iterator:keys',
		'standard-map:keys',
		'wrap-iterator:iterator',
		'standard-map:iterator',
		'wrap-iterator:keyValueIterator',
		'standard-map:keyValueIterator',
		'standard-map:copy',
		'format-of-array',
		'standard-map:toString',
		'format-create-array',
		'format-has-next',
		'format-next',
		'format-push',
		textRole,
		'format-join',
		'standard-map:clear'
	]
	if (conversion.runtimeUseOccurrences.map(use => use.role).join(',') !== expectedRoles.join(','))
		throw new Error(`IMap conversion ${conversion.id} does not record final structured-expression order`)
}

const generated = fs.readFileSync('out/Main.ml', 'utf8')
for (const key of ['string', 'int', 'object']) {
	for (const operation of ['set', 'get', 'exists', 'remove', 'keys', 'values', 'pairs', 'copy', 'clear']) {
		if (!generated.includes(`HxMap.${operation}_${key}`))
			throw new Error(`generated syntax did not consume HxMap.${operation}_${key}`)
	}
	if (generated.includes(`HxMap.toString_${key}`))
		throw new Error(`generated syntax retained the old HxMap.toString_${key} placeholder`)
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
	|| report.summary.iMapInterfaceConversionCount !== 5
	|| report.summary.iMapInterfaceCallCount !== 55
	|| report.summary.iMapStorageAliasCount !== 6) {
	throw new Error('reflaxe.ocaml inspection did not preserve the sealed standard IMap adapters')
}
NODE

node <<'NODE'
const fs = require('fs')
const crypto = require('crypto')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const local = report.iMapInterfaceConversions.find(conversion => conversion.role === 'local-initializer')
if (!local)
	throw new Error('the IMap fixture has no local conversion identity to corrupt')
local.roleIdentity = '67681'
report.iMapInterfaceRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify({
	conversions: report.iMapInterfaceConversions,
	calls: report.iMapInterfaceCalls,
	storageAliases: report.iMapStorageAliases
})).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a request-local numeric IMap role identity" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const crypto = require('crypto')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
report.iMapInterfaceConversions[0].sourceCarrierTypeId = 'HxMap.wrong_map'
report.iMapInterfaceRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify({
	conversions: report.iMapInterfaceConversions,
	calls: report.iMapInterfaceCalls,
	storageAliases: report.iMapStorageAliases
})).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a corrupted standard IMap storage carrier" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const requirement = report.runtimeRequirements.find(item => item.id.endsWith(':runtime:haxe-map'))
requirement.rootModules = ['HxIterator']
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a corrupted standard IMap runtime requirement" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const crypto = require('crypto')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const nested = report.iMapInterfaceConversions.find(conversion => conversion.functionId.includes('|nested-function|'))
if (!nested)
	throw new Error('the IMap fixture has no nested conversion to corrupt')
nested.pipelineRevision = 'ocaml-function-plans-v88'
report.iMapInterfaceRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify({
	conversions: report.iMapInterfaceConversions,
	calls: report.iMapInterfaceCalls,
	storageAliases: report.iMapStorageAliases
})).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a nested IMap conversion labeled as a root-function decision" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const crypto = require('crypto')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
// Decision IDs include the plan revision, so their sorted order may change
// after a legitimate schema update. Select the semantic case this negative
// test owns instead of assuming it remains the first report entry.
const rootStringAlias = report.iMapStorageAliases.find(alias =>
	alias.standardKeyKind === 'string'
	&& !alias.functionId.includes('|nested-function|'))
if (!rootStringAlias)
	throw new Error('the IMap fixture has no root string-map alias to corrupt')
rootStringAlias.preservedCarrierTypeId = 'HxMap.int_map'
report.iMapInterfaceRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify({
	conversions: report.iMapInterfaceConversions,
	calls: report.iMapInterfaceCalls,
	storageAliases: report.iMapStorageAliases
})).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a storage alias with the wrong raw carrier" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const crypto = require('crypto')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const rootStringAlias = report.iMapStorageAliases.find(alias =>
	alias.standardKeyKind === 'string'
	&& !alias.functionId.includes('|nested-function|'))
if (!rootStringAlias)
	throw new Error('the IMap fixture has no root string-map alias to corrupt')
rootStringAlias.uses[0].nativeOperation = 'exists_int'
report.iMapInterfaceRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify({
	conversions: report.iMapInterfaceConversions,
	calls: report.iMapInterfaceCalls,
	storageAliases: report.iMapStorageAliases
})).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a storage alias consumed by the wrong native Map operation" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const crypto = require('crypto')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const nested = report.iMapStorageAliases.find(alias => alias.functionId.includes('|nested-function|'))
if (!nested)
	throw new Error('the IMap fixture has no nested storage alias to corrupt')
nested.pipelineRevision = 'ocaml-function-plans-v88'
report.iMapInterfaceRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify({
	conversions: report.iMapInterfaceConversions,
	calls: report.iMapInterfaceCalls,
	storageAliases: report.iMapStorageAliases
})).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a nested storage alias labeled as a root-function decision" >&2
	exit 1
fi

echo "STANDARD_IMAP_TYPED_TARGET:PASS"
