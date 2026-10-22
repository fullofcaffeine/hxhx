#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (report.structuralFieldModel !== 'typed-structural-field-overlap-v5')
	throw new Error('expected the exact enum recovery field model')
const reads = report.structuralFields.filter(field => field.loadConversion === 'unbox-enum')
if (reads.length === 0)
	throw new Error('fixture did not exercise a stored enum load')
for (const name of ['key', 'value', 'next', 'hasNext']) {
	if (!reads.some(field => field.fieldName === name))
		throw new Error(`fixture did not retain its ${name} enum read`)
}
if (!reads.some(field => field.enumLoadTarget?.nullable === true)
	|| !reads.some(field => field.enumLoadTarget?.nullable === false))
	throw new Error('fixture did not retain both nullable and required enum storage')
for (const field of reads) {
	const target = field.enumLoadTarget
	if (field.operation !== 'read-stored-field' || target?.semanticTypeId !== '_Main.Payload'
		|| target.carrierTypeId !== 'haxe-enum-native-variant-carrier-v1:_Main.Payload')
		throw new Error('enum read lost its exact native variant identity')
	const requirementId = `${field.id}:runtime:haxe-structural-enum-carrier`
	const requirement = report.runtimeRequirements.find(entry => entry.id === requirementId)
	if (requirement?.semanticCapability !== 'haxe-structural-enum-carrier'
		|| requirement.subject?.id !== target.semanticTypeId
		|| requirement.rootModules?.join(',') !== 'HxEnum')
		throw new Error('enum read lost its exact runtime owner')
	const uses = field.runtimeUseOccurrences
	if (uses.length !== 2 || uses[0].exactSymbol !== 'HxEnum.unbox_or_obj' || uses[0].role !== 'unbox-enum'
		|| uses[0].requirementId !== requirementId || uses[1].exactSymbol !== 'HxAnon.get'
		|| uses.some((use, index) => use.order !== index || use.ownerId !== field.id || use.cardinality !== 1))
		throw new Error('enum field runtime-use order or ownership changed')
}
for (const field of report.structuralFields.filter(field => field.operation.startsWith('project-tuple-'))) {
	if (field.enumLoadTarget !== null || field.loadConversion !== null || field.runtimeUseOccurrences.length !== 0)
		throw new Error('native Map tuples borrowed ordinary stored-enum recovery')
}
const output = fs.readFileSync('out/Main.ml', 'utf8')
if (!output.includes('HxEnum.unbox_or_obj "_Main.Payload"') || !output.includes('Stdlib.snd'))
	throw new Error('fixture did not materialize enum recovery and native tuple projection')
NODE

repo_root="$(cd ../../../.. && pwd)"
fixture_root="$PWD"
inspector_dir="$(mktemp -d)"
lowering_backup="$(mktemp)"
cp out/ocaml_lowering_report.json "$lowering_backup"
trap 'cp "$lowering_backup" out/ocaml_lowering_report.json; rm -f "$lowering_backup"; rm -rf "$inspector_dir"' EXIT
(
	cd "$repo_root"
	"${HAXE_BIN:-haxe}" -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' -D reflaxe_runtime \
		-main reflaxe.ocaml.tooling.ReflaxeOcamlRun --neko "$inspector_dir/inspect.n"
)
inspect() {
	(
		cd "$repo_root"
		neko "$inspector_dir/inspect.n" inspect --project "$fixture_root" --output out --require-lowering --json
	)
}
inspect >"$inspector_dir/valid.json"
for corruption in enum-identity missing-target nullable helper missing-helper; do
	cp "$lowering_backup" out/ocaml_lowering_report.json
	node - "$corruption" <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const field = report.structuralFields.find(field => field.loadConversion === 'unbox-enum')
switch (process.argv[2]) {
	case 'enum-identity': field.enumLoadTarget.semanticTypeId = '_Main.Other'; break
	case 'missing-target': delete field.enumLoadTarget; break
	case 'nullable': field.enumLoadTarget.nullable = !field.enumLoadTarget.nullable; break
	case 'helper': field.runtimeUseOccurrences[0].exactSymbol = 'HxEnum.box_if_needed'; break
	case 'missing-helper': field.runtimeUseOccurrences.shift(); break
}
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
	if inspect >"$inspector_dir/$corruption.json" 2>"$inspector_dir/$corruption.stderr"; then
		echo "inspection accepted structural enum corruption: $corruption" >&2
		exit 1
	fi
done
cp "$lowering_backup" out/ocaml_lowering_report.json
echo "STRUCTURAL_ENUM_FIELD_READ:PASS"
