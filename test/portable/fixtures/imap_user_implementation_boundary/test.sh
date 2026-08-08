#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (report.schemaVersion !== 65
	|| report.iMapInterfaceModel !== 'typed-imap-interface-adapter-v1'
	|| report.iMapInterfaceConversionCount !== report.iMapInterfaceConversions?.length
	|| report.iMapInterfaceCallCount !== report.iMapInterfaceCalls?.length
	|| report.iMapInterfaceConversionCount !== 6
	|| report.iMapInterfaceCallCount !== 25) {
	throw new Error('the fixture did not produce the complete current IMap interface inventory')
}
if (report.calls?.some(call => call.kind === 'standard-imap-method'))
	throw new Error('the obsolete standard-only IMap call path still owns emitted calls')

const expectedMethods = {
	get: {arguments: ['String'], result: 'Null<Int>'},
	set: {arguments: ['String', 'Int'], result: 'Void'},
	exists: {arguments: ['String'], result: 'Bool'},
	remove: {arguments: ['String'], result: 'Bool'},
	keys: {arguments: [], result: 'Iterator<String>'},
	iterator: {arguments: [], result: 'Iterator<Int>'},
	keyValueIterator: {arguments: [], result: 'KeyValueIterator<String, Int>'},
	copy: {arguments: [], result: 'haxe.IMap<String, Int>'},
	toString: {arguments: [], result: 'String'},
	clear: {arguments: [], result: 'Void'}
}
const userConversions = report.iMapInterfaceConversions.filter(conversion => conversion.sourceKind === 'user-implementation')
if (userConversions.length !== 3)
	throw new Error(`expected three user adapters, found ${userConversions.length}`)
for (const conversion of userConversions) {
	if (conversion.targetCarrierTypeId !== 'Obj.t(haxe_Constraints.imap_t)'
		|| conversion.standardKeyKind !== null
		|| conversion.runtimeCapabilities.length !== 0
		|| conversion.methods.length !== Object.keys(expectedMethods).length) {
		throw new Error(`user conversion ${conversion.id} does not preserve the checked interface surface`)
	}
	for (const method of conversion.methods) {
		const expected = expectedMethods[method.name]
		if (!expected
			|| method.argumentSemanticTypeIds.join(',') !== expected.arguments.join(',')
			|| method.resultSemanticTypeId !== expected.result) {
			throw new Error(`user conversion ${conversion.id} has a wrong ${method.name} signature`)
		}
	}
}

const expectedStandard = {
	'standard-string-map': {key: 'String', kind: 'string', carrier: 'HxMap.string_map', source: 'HxMap<Int>', keyText: 'exact-string', valueText: 'exact-int'},
	'standard-int-map': {key: 'Int', kind: 'int', carrier: 'HxMap.int_map', source: 'HxMap<String>', keyText: 'exact-int', valueText: 'exact-string'},
	'standard-object-map': {key: '_Main.ObjectKey', kind: 'object-identity', carrier: 'HxMap.obj_map', source: 'HxMap<_Main.ObjectKey, Int>', keyText: 'dynamic-object', valueText: 'exact-int'}
}
for (const [sourceKind, expected] of Object.entries(expectedStandard)) {
	const conversion = report.iMapInterfaceConversions.find(item => item.sourceKind === sourceKind)
	if (!conversion
		|| conversion.keySemanticTypeId !== expected.key
		|| conversion.standardKeyKind !== expected.kind
		|| conversion.keyStringifier !== expected.keyText
		|| conversion.valueStringifier !== expected.valueText
		|| conversion.sourceCarrierTypeId !== expected.carrier
		|| conversion.sourceSemanticTypeId !== expected.source
		|| conversion.methods.map(method => method.name).join(',') !== Object.keys(expectedMethods).join(',')) {
		throw new Error(`standard conversion ${sourceKind} lost its exact source and storage carrier`)
	}
	const requirementIds = conversion.runtimeCapabilities.map(capability => `${conversion.id}:runtime:${capability}`).sort()
	const actualIds = report.runtimeRequirements.filter(requirement => requirement.decisionId === conversion.id).map(requirement => requirement.id).sort()
	if (requirementIds.join(',') !== actualIds.join(','))
		throw new Error(`standard conversion ${conversion.id} does not own its exact runtime requirements`)
}

const operations = new Set(report.iMapInterfaceCalls.map(call => call.operation))
for (const operation of ['set', 'get', 'exists', 'remove', 'keys', 'iterator', 'key-value-iterator', 'copy', 'to-string', 'clear']) {
	if (!operations.has(operation))
		throw new Error(`the interface-call inventory does not exercise ${operation}`)
}
for (const call of report.iMapInterfaceCalls) {
	if (call.pipelineRevision !== 'ocaml-function-plans-v76'
		|| call.receiverCarrierTypeId !== 'Obj.t(haxe_Constraints.imap_t)'
		|| call.receiverSemanticTypeId !== `haxe.IMap<${call.keySemanticTypeId}, ${call.valueSemanticTypeId}>`) {
		throw new Error(`interface call ${call.id} has a stale or conflicting receiver boundary`)
	}
}

const generated = fs.readFileSync('out/Main.ml', 'utf8')
if (!generated.includes('taggedstringmap_get__impl __imap_user_receiver_')
	|| !generated.includes('taggedstringmap_toString__impl __imap_user_receiver_')
	|| !generated.includes('({ __hx_type = HxType.class_ "haxe.IMap";')
	|| !generated.includes('HxMap.get_string __standard_imap_receiver_')
	|| !generated.includes('HxMap.get_int __standard_imap_receiver_')
	|| !generated.includes('HxMap.get_object __standard_imap_receiver_')) {
	throw new Error('generated adapters do not call the real user methods and the three proven standard carriers')
}
NODE

unsealed_call_log="$(mktemp)"
if haxe unsealed-call.hxml >"$unsealed_call_log" 2>&1; then
	echo "A static IMap call unexpectedly reached syntax without a function-owned dispatch plan" >&2
	exit 1
fi
if ! grep -Fq '[ocaml-call:plan-invariant]' "$unsealed_call_log" \
	|| ! grep -Fq 'exact IMap interface call reached syntax without its sealed dispatch decision' "$unsealed_call_log"; then
	echo "The unsealed IMap call did not report the stable hard-cut diagnostic" >&2
	cat "$unsealed_call_log" >&2
	exit 1
fi

unsealed_conversion_log="$(mktemp)"
if haxe unsealed-conversion.hxml >"$unsealed_conversion_log" 2>&1; then
	echo "A static concrete Map unexpectedly became IMap without a conversion plan" >&2
	exit 1
fi
if ! grep -Fq '[ocaml-call:plan-invariant]' "$unsealed_conversion_log" \
	|| ! grep -Fq 'concrete value reached an IMap boundary without an active interface-conversion plan' "$unsealed_conversion_log"; then
	echo "The unsealed IMap conversion did not report the stable hard-cut diagnostic" >&2
	cat "$unsealed_conversion_log" >&2
	exit 1
fi

repo_root="$(cd ../../../.. && pwd)"
fixture_root="$PWD"
inspection_report="$(mktemp)"
lowering_backup="$(mktemp)"
cp out/ocaml_lowering_report.json "$lowering_backup"
trap 'cp "$lowering_backup" out/ocaml_lowering_report.json; rm -f "$inspection_report" "$lowering_backup" "$unsealed_call_log" "$unsealed_conversion_log"' EXIT

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
if (report.schemaVersion !== 42
	|| !report.summary?.valid
	|| report.summary.iMapInterfaceConversionCount !== 6
	|| report.summary.iMapInterfaceCallCount !== 25) {
	throw new Error('reflaxe.ocaml inspection did not preserve the complete IMap interface inventory')
}
NODE

mutate_report() {
	node - "$1" <<'NODE'
const fs = require('fs')
const crypto = require('crypto')
const mutation = process.argv[2]
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
switch (mutation) {
	case 'missing-conversion':
		report.iMapInterfaceConversions.pop()
		break
	case 'wrong-receiver-carrier':
		report.iMapInterfaceCalls[0].receiverCarrierTypeId = 'HxMap.string_map'
		break
	case 'wrong-value-type': {
		const conversion = report.iMapInterfaceConversions.find(item => item.sourceKind === 'user-implementation')
		conversion.methods.find(method => method.name === 'set').argumentSemanticTypeIds[1] = 'String'
		break
	}
	case 'wrong-key-type': {
		const conversion = report.iMapInterfaceConversions.find(item => item.sourceKind === 'user-implementation')
		conversion.methods.find(method => method.name === 'set').argumentSemanticTypeIds[0] = 'Int'
		break
	}
	case 'missing-retained-method':
		report.iMapInterfaceConversions[0].methods.pop()
		break
	case 'stale-call':
		report.iMapInterfaceCalls[0].pipelineRevision = 'ocaml-function-plans-v66'
		break
	case 'wrong-runtime-owner':
		report.runtimeRequirements.find(item => item.id.endsWith(':runtime:haxe-map')).rootModules = ['HxIterator']
		break
	default:
		throw new Error(`unknown mutation ${mutation}`)
}
report.iMapInterfaceRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify({
	conversions: report.iMapInterfaceConversions,
	calls: report.iMapInterfaceCalls
})).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
}

expect_inspection_rejection() {
	local mutation="$1"
	cp "$lowering_backup" out/ocaml_lowering_report.json
	mutate_report "$mutation"
	if inspect >"$inspection_report" 2>/dev/null; then
		echo "reflaxe.ocaml inspection accepted the $mutation IMap evidence mutation" >&2
		exit 1
	fi
}

expect_inspection_rejection missing-conversion
expect_inspection_rejection wrong-receiver-carrier
expect_inspection_rejection wrong-value-type
expect_inspection_rejection wrong-key-type
expect_inspection_rejection missing-retained-method
expect_inspection_rejection stale-call
expect_inspection_rejection wrong-runtime-owner

echo "IMAP_USER_IMPLEMENTATION_BOUNDARY:PASS"
