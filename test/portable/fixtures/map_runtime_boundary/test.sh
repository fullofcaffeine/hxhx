#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
FIXTURE_ROOT="$PWD"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_runtime_requirement_report.json"
LOWERING_REPORT_FILE="out/ocaml_lowering_report.json"
BUILDER_FILE="$ROOT/packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx"
REPORT_COPY="$(mktemp)"
LOWERING_REPORT_COPY="$(mktemp)"
INSPECTION_REPORT="$(mktemp)"
trap 'rm -f "$REPORT_COPY" "$LOWERING_REPORT_COPY" "$INSPECTION_REPORT"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ] || [ ! -f "$LOWERING_REPORT_FILE" ] || [ ! -f "$BUILDER_FILE" ]; then
	echo "Missing generated Map source, lowering evidence, runtime requirement report, or target builder" >&2
	exit 1
fi

rm -f out/oracle.interp out/oracle.js out/oracle.js.stdout out/oracle.n out/oracle.neko.stdout out/invalid-source-identity.log

node - "$SOURCE_FILE" "$REPORT_FILE" "$LOWERING_REPORT_FILE" "$BUILDER_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const lowering = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'))
const builder = fs.readFileSync(process.argv[5], 'utf8')

function fail(message) {
	throw new Error(message)
}

const expectedMapOperations = [
	'create_string',
	'set_string',
	'get_string',
	'exists_string',
	'remove_string',
	'clear_string',
	'copy_string',
	'keys_string',
	'values_string',
	'pairs_string',
	'create_int',
	'set_int',
	'get_int',
	'exists_int',
	'remove_int',
	'clear_int',
	'copy_int',
	'keys_int',
	'values_int',
	'pairs_int',
	'create_object',
	'set_object',
	'get_object',
	'exists_object',
	'remove_object',
	'clear_object',
	'copy_object',
	'keys_object',
	'values_object',
	'pairs_object'
]
for (const operation of expectedMapOperations) {
	if (!source.includes(`HxMap.${operation}`))
		fail(`generated syntax does not consume typed HxMap operation ${operation}`)
}
for (const carrier of [
	'mutable stringValues : int HxMap.string_map',
	'mutable intValues : string HxMap.int_map',
	'mutable objectValues : (objectkey_t, int) HxMap.obj_map'
]) {
	if (!source.includes(carrier))
		fail(`standard Map field did not preserve its typed source carrier: ${carrier}`)
}
if (!source.includes('HxIterator.of_array'))
	fail('generated Map iteration does not consume the typed HxIterator adapter')
if (!source.includes('Stdlib.fst') || !source.includes('Stdlib.snd') || source.includes('HxAnon.get'))
	fail('standard Map pairs must use proven tuple projections rather than anonymous-object field lookup')

const tupleDecisions = (lowering.structuralFields || []).filter(decision => decision.keyValueTupleTarget)
const expectedPairSources = [
	'haxe.ds.NativeHxMapIterator.of_array(haxe.ds.NativeHxMap.pairs_string)',
	'haxe.ds.NativeHxMapIterator.of_array(haxe.ds.NativeHxMap.pairs_int)',
	'haxe.ds.NativeHxMapIterator.of_array(haxe.ds.NativeHxMap.pairs_object)'
]
if (tupleDecisions.length === 0)
	fail('lowering report contains no typed standard Map pair projections')
for (const decision of tupleDecisions) {
	const target = decision.keyValueTupleTarget
	if (target.iteratorProducerKind !== 'target-native-standard-map-call'
		|| target.iteratorProducerId !== 'target-native-standard-map-pair-producer-v1'
		|| target.proofId !== 'standard-map-key-value-tuple-projection-v3'
		|| !expectedPairSources.includes(target.iteratorProducerSourceId)
		|| decision.runtimeModule !== 'Stdlib'
		|| !['fst', 'snd'].includes(decision.runtimeOperation)
		|| decision.runtimeRequirementIds.length !== 0) {
		fail(`Map pair field lacks the exact target-native tuple proof: ${JSON.stringify(decision)}`)
	}
}
for (const pairSource of expectedPairSources) {
	const projections = new Set(tupleDecisions
		.filter(decision => decision.keyValueTupleTarget.iteratorProducerSourceId === pairSource)
		.map(decision => decision.keyValueTupleTarget.projection))
	if (!projections.has('fst') || !projections.has('snd'))
		fail(`Map pair producer ${pairSource} did not prove both key and value projections`)
}
for (const operation of ['toString_string', 'toString_int', 'toString_object']) {
	if (source.includes(`HxMap.${operation}`))
		fail(`Map text still delegates Haxe behavior to runtime placeholder ${operation}`)
}
for (const legacyClassCheck of [
	'isHaxeDsStringMapClass',
	'isHaxeDsIntMapClass',
	'isHaxeDsObjectMapClass'
]) {
	if (builder.includes(legacyClassCheck))
		fail(`target syntax still recognizes standard Map class through ${legacyClassCheck}`)
}

const requirements = report.requirements || []
const mapRequirements = requirements.filter(requirement =>
	requirement.semanticCapability === 'haxe-map'
	&& requirement.rootModules.join(',') === 'HxMap'
	&& requirement.sourceKind === 'native-boundary'
	&& requirement.sourceId.startsWith('haxe-declaration:haxe.ds.'))
const iteratorRequirements = requirements.filter(requirement =>
	requirement.semanticCapability === 'haxe-iterator'
	&& requirement.rootModules.join(',') === 'HxIterator'
	&& requirement.sourceKind === 'native-boundary'
	&& requirement.sourceId === 'haxe-declaration:haxe.ds.NativeHxMapIterator::haxe.ds.NativeHxMapIterator.of_array')

for (const operation of expectedMapOperations) {
	if (!mapRequirements.some(requirement =>
		requirement.subject.id.endsWith(` -> HxMap.${operation}`))) {
		fail(`runtime report does not explain typed HxMap operation ${operation}`)
	}
}
if (iteratorRequirements.length !== 1)
	fail(`expected one canonical typed HxIterator requirement, got ${iteratorRequirements.length}`)
if (!report.recordedSemanticCapabilities.includes('haxe-map')
	|| !report.recordedSemanticCapabilities.includes('haxe-iterator'))
	fail('runtime report did not expose both Map and iterator semantic capabilities')
for (const moduleName of ['HxMap', 'HxIterator']) {
	if (!report.requirementRootModules.includes(moduleName)
		|| !report.compilerObservedModulesWithRequirementRoots.includes(moduleName)
		|| report.compilerObservedModulesWithoutRequirementRoots.includes(moduleName)) {
		fail(`${moduleName} is not fully explained by the typed runtime requirements`)
	}
}
NODE

cp "$LOWERING_REPORT_FILE" "$LOWERING_REPORT_COPY"
inspect() {
	(
		cd "$ROOT"
		haxe -cp packages/reflaxe.ocaml/src \
			--macro 'nullSafety("reflaxe.ocaml")' \
			--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
			inspect --project "$FIXTURE_ROOT" --output out --require-lowering --json
	)
}

inspect >"$INSPECTION_REPORT"
node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const field = report.structuralFields.find(decision =>
	decision.keyValueTupleTarget?.iteratorProducerSourceId ===
	'haxe.ds.NativeHxMapIterator.of_array(haxe.ds.NativeHxMap.pairs_string)')
if (!field)
	throw new Error('Map fixture has no string-key target-native pair proof to corrupt')
field.keyValueTupleTarget.iteratorProducerSourceId =
	'haxe.ds.NativeHxMapIterator.of_array(haxe.ds.NativeHxMap.pairs_int)'
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$INSPECTION_REPORT" 2>&1; then
	echo "reflaxe.ocaml inspection accepted a target-native Map proof with conflicting key ownership" >&2
	exit 1
fi
if ! grep -Fq '[ocaml-structural-field:invalid-key-value-proof]' "$INSPECTION_REPORT"; then
	echo "Conflicting target-native Map proof failed outside the typed ownership contract" >&2
	cat "$INSPECTION_REPORT" >&2
	exit 1
fi
cp "$LOWERING_REPORT_COPY" "$LOWERING_REPORT_FILE"

cp "$REPORT_FILE" "$REPORT_COPY"
haxe build.hxml -D ocaml_build=native
cmp "$REPORT_COPY" "$REPORT_FILE"

haxe -cp src -main Main --interp >out/oracle.interp
haxe -cp src -main Main -js out/oracle.js
node out/oracle.js >out/oracle.js.stdout
haxe -cp src -main Main -neko out/oracle.n
neko out/oracle.n >out/oracle.neko.stdout

diff -u expected.stdout out/oracle.interp
diff -u expected.stdout out/oracle.js.stdout
diff -u expected.stdout out/oracle.neko.stdout

INVALID_IDENTITY_LOG="out/invalid-source-identity.log"
if haxe build.hxml -D ocaml_no_build -D map_invalid_source_identity >"$INVALID_IDENTITY_LOG" 2>&1; then
	echo "Malformed typed declaration identity unexpectedly compiled" >&2
	exit 1
fi
if ! grep -Fq 'reflaxe.ocaml [typed-declaration-identity]: :realPath on a class marker declaration requires exactly one constant source name.' "$INVALID_IDENTITY_LOG"; then
	echo "Malformed typed declaration identity did not fail at the typed identity boundary" >&2
	cat "$INVALID_IDENTITY_LOG" >&2
	exit 1
fi

echo "REFLAXE_OCAML_TYPED_MAP_RUNTIME_BOUNDARY:PASS"
