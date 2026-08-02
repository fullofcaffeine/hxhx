#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const lowering = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (lowering.schemaVersion !== 52
	|| lowering.structuralFieldModel !== 'typed-structural-field-overlap-v1') {
	throw new Error('the lowering report has no current typed structural-field model')
}

const fields = lowering.structuralFields ?? []
if (fields.length < 10 || lowering.structuralFieldCount !== fields.length)
	throw new Error('the fixture did not seal the focused read and real ListSort field operations')
const operations = new Set(fields.map(field => field.operation))
for (const operation of ['read-stored-field', 'write-stored-field']) {
	if (!operations.has(operation))
		throw new Error(`the fixture did not seal ${operation}`)
}
const fieldNames = new Set(fields.map(field => field.fieldName))
for (const fieldName of ['next', 'hasNext']) {
	if (!fieldNames.has(fieldName))
		throw new Error(`the fixture did not seal the ordinary ${fieldName} field`)
}

for (const field of fields) {
	if (!['next', 'hasNext'].includes(field.fieldName)
		|| field.iteratorTarget !== null
		|| field.receiverCarrierTypeId !== 'Obj.t'
		|| field.runtimeModule !== 'HxAnon'
		|| field.runtimeOperation !== (field.operation === 'write-stored-field' ? 'set' : 'get')
		|| field.pipelineRevision !== 'ocaml-function-plans-v65') {
		throw new Error(`stored structural field ${field.id} is not fully sealed`)
	}
	const requirements = lowering.runtimeRequirements.filter(requirement => requirement.decisionId === field.id)
	if (requirements.length !== 1
		|| requirements[0].id !== `${field.id}:runtime:haxe-structural-field`
		|| requirements[0].semanticCapability !== 'haxe-structural-field'
		|| requirements[0].rootModules?.join(',') !== 'HxAnon') {
		throw new Error(`stored structural field ${field.id} does not own its exact HxAnon requirement`)
	}
}

const listSortFields = fields.filter(field => field.source.file === 'haxe-stdlib/haxe/ds/ListSort.hx')
if (listSortFields.length < 6)
	throw new Error('the real ListSort implementation did not contribute its expected next reads and writes')

const generated = fs.readFileSync('out/haxe_ds_ListSort.ml', 'utf8')
if (!generated.includes('HxAnon.get') || !generated.includes('HxAnon.set'))
	throw new Error('generated ListSort did not exercise both stored next operations')
if (/HxIterator\.(hasNext|next)/.test(generated))
	throw new Error('generated ListSort still mistakes an ordinary next field for an Iterator method')
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
if (report.schemaVersion !== 31
	|| !report.summary?.valid
	|| report.lowering?.structuralFields?.length < 10
	|| report.summary.structuralFieldCount !== report.lowering.structuralFields.length) {
	throw new Error('reflaxe.ocaml inspection did not preserve the sealed structural-field decisions')
}
NODE

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
report.structuralFields[0].operation = 'capture-iterator-method'
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a stored field changed into an unowned Iterator method" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const requirement = report.runtimeRequirements.find(item => item.id.endsWith(':runtime:haxe-structural-field'))
requirement.rootModules = ['HxIterator']
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a stored field with a corrupted runtime owner" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
report.structuralFields.pop()
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a missing structural-field decision" >&2
	exit 1
fi

echo "STRUCTURAL_NEXT_FIELD_TYPED_OWNERSHIP:PASS"
