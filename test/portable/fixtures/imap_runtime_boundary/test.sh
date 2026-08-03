#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (report.schemaVersion !== 64
	|| report.callModel !== 'typed-ocaml-directional-call-boundary-v20') {
	throw new Error('the IMap fixture did not produce the current sealed call-report schema')
}
if (report.iMapInterfaceModel !== 'typed-imap-interface-adapter-v1'
	|| report.iMapInterfaceConversionCount !== 3
	|| report.iMapInterfaceCallCount !== 53
	|| report.calls?.some(call => call.kind === 'standard-imap-method')) {
	throw new Error('the IMap fixture did not hard-cut standard maps to the shared interface adapter')
}
const calls = report.iMapInterfaceCalls
if (calls.some(call =>
	call.pipelineRevision !== 'ocaml-function-plans-v74'
	|| call.receiverCarrierTypeId !== 'Obj.t(haxe_Constraints.imap_t)'
	|| call.receiverSemanticTypeId !== `haxe.IMap<${call.keySemanticTypeId}, ${call.valueSemanticTypeId}>`)) {
	throw new Error('the IMap fixture did not seal all calls against the exact interface receiver')
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
const keyKinds = new Set(conversions.map(conversion => conversion.standardKeyKind))
if (![...['string', 'int', 'object-identity']].every(kind => keyKinds.has(kind))
	|| conversions.some(conversion =>
		conversion.sourceKind === 'user-implementation'
		|| conversion.methods.length !== 10
		|| conversion.targetCarrierTypeId !== 'Obj.t(haxe_Constraints.imap_t)')) {
	throw new Error('the IMap fixture did not preserve all three proven standard storage carriers')
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
if (formatted.length !== 3
	|| formatted.some(conversion =>
		!conversion.runtimeCapabilities.includes('haxe-array')
		|| (!conversion.runtimeCapabilities.includes('haxe-string-text')
			&& !conversion.runtimeCapabilities.includes('haxe-dynamic-text')))) {
	throw new Error('Map.toString was not sealed as typed pair traversal and entry formatting')
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
if (report.schemaVersion !== 41
	|| !report.summary?.valid
	|| report.summary.iMapInterfaceConversionCount !== 3
	|| report.summary.iMapInterfaceCallCount !== 53) {
	throw new Error('reflaxe.ocaml inspection did not preserve the sealed standard IMap adapters')
}
NODE

node <<'NODE'
const fs = require('fs')
const crypto = require('crypto')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
report.iMapInterfaceConversions[0].sourceCarrierTypeId = 'HxMap.wrong_map'
report.iMapInterfaceRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify({
	conversions: report.iMapInterfaceConversions,
	calls: report.iMapInterfaceCalls
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

echo "STANDARD_IMAP_TYPED_TARGET:PASS"
