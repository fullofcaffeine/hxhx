#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (report.schemaVersion !== 49
	|| report.callModel !== 'typed-ocaml-directional-call-boundary-v18') {
	throw new Error('the IMap fixture did not produce the current sealed call-report schema')
}
const calls = report.calls?.filter(call => call.kind === 'standard-imap-method') ?? []
if (calls.length !== 53
	|| calls.some(call =>
		call.pipelineRevision !== 'ocaml-function-plans-v62'
		|| call.receiver !== null
		|| call.arguments?.length !== 0
		|| call.result !== null
		|| !call.standardIMapTarget)) {
	throw new Error('the IMap fixture did not seal all standard calls without ordinary callable crossings')
}
const operations = new Set(calls.map(call => call.standardIMapTarget.operation))
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
const keyKinds = new Set(calls.map(call => call.standardIMapTarget.keyKind))
if (![...['string', 'int', 'object-identity']].every(kind => keyKinds.has(kind)))
	throw new Error('the IMap fixture did not cover all admitted standard key carriers')
for (const call of calls) {
	const target = call.standardIMapTarget
	const expectedRequirementIds = target.runtimeCapabilities.map(capability => `${call.id}:runtime:${capability}`)
	const actualRequirements = report.runtimeRequirements.filter(requirement => requirement.decisionId === call.id)
	if (actualRequirements.length !== expectedRequirementIds.length
		|| actualRequirements.some(requirement => !expectedRequirementIds.includes(requirement.id))) {
		throw new Error(`standard IMap call ${call.id} does not own its exact runtime requirements`)
	}
	if (call.evaluationSchedule?.[0]?.kind !== 'materialize-receiver'
		|| call.evaluationSchedule.at(-1)?.kind !== 'invoke-callee'
		|| call.evaluationSchedule.length !== target.argumentSemanticTypeIds.length + 2) {
		throw new Error(`standard IMap call ${call.id} lost receiver-first source-order evaluation`)
	}
}
const formatted = calls.filter(call => call.standardIMapTarget.operation === 'to-string')
if (formatted.length !== 3
	|| formatted.some(call =>
		call.standardIMapTarget.runtimeFunction.startsWith('toString_')
		|| call.standardIMapTarget.resultForm !== 'formatted-entries'
		|| !call.standardIMapTarget.runtimeCapabilities.includes('haxe-array'))) {
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
const standardCalls = report.lowering?.calls?.filter(call => call.kind === 'standard-imap-method') ?? []
if (report.schemaVersion !== 29 || !report.summary?.valid || standardCalls.length !== 53)
	throw new Error('reflaxe.ocaml inspection did not preserve the sealed standard IMap targets')
NODE

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const call = report.calls.find(item => item.kind === 'standard-imap-method')
call.standardIMapTarget.runtimeFunction = 'corrupted_runtime_function'
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a corrupted standard IMap runtime target" >&2
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
