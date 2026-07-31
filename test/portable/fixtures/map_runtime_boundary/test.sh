#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_runtime_requirement_report.json"
BUILDER_FILE="$ROOT/packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx"
REPORT_COPY="$(mktemp)"
trap 'rm -f "$REPORT_COPY"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ] || [ ! -f "$BUILDER_FILE" ]; then
	echo "Missing generated Map source, runtime requirement report, or target builder" >&2
	exit 1
fi

rm -f out/oracle.interp out/oracle.js out/oracle.js.stdout out/oracle.n out/oracle.neko.stdout out/invalid-source-identity.log

node - "$SOURCE_FILE" "$REPORT_FILE" "$BUILDER_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const builder = fs.readFileSync(process.argv[4], 'utf8')

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
if ! grep -Fq 'reflaxe.ocaml [typed-declaration-identity]: :realPath on a class requires exactly one constant source name.' "$INVALID_IDENTITY_LOG"; then
	echo "Malformed typed declaration identity did not fail at the typed identity boundary" >&2
	cat "$INVALID_IDENTITY_LOG" >&2
	exit 1
fi

echo "REFLAXE_OCAML_TYPED_MAP_RUNTIME_BOUNDARY:PASS"
