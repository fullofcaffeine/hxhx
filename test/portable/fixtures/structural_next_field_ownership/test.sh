#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const lowering = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (lowering.schemaVersion !== 86
	|| lowering.structuralFieldModel !== 'typed-structural-field-overlap-v4') {
	throw new Error('the lowering report has no current typed structural-field model')
}

const fields = lowering.structuralFields ?? []
if (fields.length < 14 || lowering.structuralFieldCount !== fields.length)
	throw new Error('the fixture did not seal the focused object, Map-pair, and real ListSort field operations')
const operations = new Set(fields.map(field => field.operation))
for (const operation of ['read-stored-field', 'write-stored-field', 'project-tuple-key', 'project-tuple-value']) {
	if (!operations.has(operation))
		throw new Error(`the fixture did not seal ${operation}`)
}
const fieldNames = new Set(fields.map(field => field.fieldName))
for (const fieldName of ['next', 'hasNext', 'key', 'value']) {
	if (!fieldNames.has(fieldName))
		throw new Error(`the fixture did not seal the ordinary ${fieldName} field`)
}

const storedFields = fields.filter(field => ['read-stored-field', 'write-stored-field'].includes(field.operation))
for (const field of storedFields) {
	if (!['next', 'hasNext', 'key', 'value'].includes(field.fieldName)
		|| field.iteratorTarget !== null
		|| field.keyValueTupleTarget !== null
		|| field.receiverCarrierTypeId !== 'Obj.t'
		|| field.runtimeModule !== 'HxAnon'
		|| field.runtimeOperation !== (field.operation === 'write-stored-field' ? 'set' : 'get')
		|| field.pipelineRevision !== 'ocaml-function-plans-v112') {
		throw new Error(`stored structural field ${field.id} is not fully sealed`)
	}
	const requirements = lowering.runtimeRequirements.filter(requirement => requirement.decisionId === field.id)
	const boolField = field.fieldSemanticTypeId === 'Bool'
	const expectedRequirementIds = [
		`${field.id}:runtime:haxe-structural-field`,
		...(boolField ? [`${field.id}:runtime:haxe-structural-bool-carrier`] : [])
	]
	const requirementsById = new Map(requirements.map(requirement => [requirement.id, requirement]))
	const fieldRequirement = requirementsById.get(expectedRequirementIds[0])
	const boolRequirement = boolField ? requirementsById.get(expectedRequirementIds[1]) : null
	if (requirements.length !== expectedRequirementIds.length
		|| expectedRequirementIds.some(id => !requirementsById.has(id))
		|| fieldRequirement.semanticCapability !== 'haxe-structural-field'
		|| fieldRequirement.rootModules?.join(',') !== 'HxAnon'
		|| (boolField && (boolRequirement.semanticCapability !== 'haxe-structural-bool-carrier'
			|| boolRequirement.rootModules?.join(',') !== 'HxRuntime'))) {
		throw new Error(`stored structural field ${field.id} does not own its exact HxAnon requirement`)
	}
	const expectedUses = field.operation === 'read-stored-field'
		? [
			...(boolField ? [['HxRuntime.unbox_bool_or_obj', 'unbox-bool']] : []),
			['HxAnon.get', 'read-field']
		]
		: [
			['HxAnon.set', 'write-field'],
			...(boolField ? [['HxRuntime.box_bool', 'box-bool']] : [])
		]
	if (field.runtimeUseOccurrences?.length !== expectedUses.length)
		throw new Error(`stored structural field ${field.id} has no exact runtime-use inventory`)
	for (const [index, [symbol, role]] of expectedUses.entries()) {
		const use = field.runtimeUseOccurrences[index]
		if (use.ownerId !== field.id
			|| use.exactSymbol !== symbol
			|| use.role !== role
			|| use.order !== index
			|| use.cardinality !== 1) {
			throw new Error(`stored structural field ${field.id} has a stale runtime use at index ${index}`)
		}
	}
}

const tupleFields = fields.filter(field => field.operation.startsWith('project-tuple-'))
if (tupleFields.length !== 2)
	throw new Error(`expected exactly two Map-pair projections, found ${tupleFields.length}`)
for (const field of tupleFields) {
	const expectedProjection = field.fieldName === 'key' ? 'fst' : 'snd'
	const target = field.keyValueTupleTarget
	if (!target
		|| field.iteratorTarget !== null
		|| field.receiverCarrierTypeId !== 'tuple<String,Int>'
		|| field.runtimeModule !== 'Stdlib'
		|| field.runtimeOperation !== expectedProjection
		|| field.runtimeRequirementIds.length !== 0
		|| field.runtimeUseOccurrences?.length !== 0
		|| target.projection !== expectedProjection
		|| target.keySemanticTypeId !== 'String'
		|| target.valueSemanticTypeId !== 'Int'
		|| target.iteratorProducerKind !== 'imap-interface-call'
		|| !target.iteratorProducerId.startsWith('imap-interface-call:')
		|| target.iteratorProducerSourceId !== 'haxe.Constraints.IMap.keyValueIterator'
		|| !target.pairProducerCallId.startsWith('call:')
		|| !target.iteratorLocalId.startsWith('lexical-local-v1:')
		|| !target.pairLocalId.startsWith('lexical-local-v1:')
		|| target.proofId !== 'standard-map-key-value-tuple-projection-v3'
		|| field.pipelineRevision !== 'ocaml-function-plans-v112') {
		throw new Error(`Map-pair projection ${field.id} has no complete typed producer proof`)
	}
	if (lowering.runtimeRequirements.some(requirement => requirement.decisionId === field.id))
		throw new Error(`Stdlib tuple projection ${field.id} unexpectedly claimed a repository runtime module`)
}

const listSortFields = fields.filter(field => field.source.file === 'haxe-stdlib/haxe/ds/ListSort.hx')
if (listSortFields.length < 6)
	throw new Error('the real ListSort implementation did not contribute its expected next reads and writes')

const listSortReturns = (lowering.controls ?? []).filter(control =>
	control.kind === 'return'
	&& control.functionId.includes('haxe.ds.ListSort|ListSort|static|function|sortSingleLinked|'))
if (listSortReturns.length !== 1
	|| listSortReturns[0].payload?.conversion !== 'box-and-recover-typed-function-result'
	|| listSortReturns[0].payload?.inputCarrierTypeId !== 'ocaml-inferred-function-result'
	|| listSortReturns[0].payload?.outputCarrierTypeId !== 'ocaml-inferred-function-result'
	|| listSortReturns[0].proofId !== 'typed-function-result-early-return-control-v1') {
	throw new Error('the generic ListSort return did not use its exact function-owned typed fallback')
}

const generated = fs.readFileSync('out/haxe_ds_ListSort.ml', 'utf8')
if (!generated.includes('HxAnon.get') || !generated.includes('HxAnon.set'))
	throw new Error('generated ListSort did not exercise both stored next operations')
if (/HxIterator\.(hasNext|next)/.test(generated))
	throw new Error('generated ListSort still mistakes an ordinary next field for an Iterator method')
if (!/HxRuntime\.Hx_return __ret_\d+ -> Obj\.obj __ret_\d+/.test(generated)
	|| /HxRuntime\.Hx_return __ret_\d+ -> Obj\.magic __ret_\d+/.test(generated)) {
	throw new Error('generated ListSort did not recover its generic result through the private typed boundary')
}

const generatedMain = fs.readFileSync('out/Main.ml', 'utf8')
if (!generatedMain.includes('HxAnon.get')
	|| !generatedMain.includes('HxAnon.set')
	|| !generatedMain.includes('Stdlib.fst')
	|| !generatedMain.includes('Stdlib.snd')) {
	throw new Error('generated Main does not preserve stored key/value fields and proven Map-pair projections')
}
NODE

tuple_write_log="$(mktemp)"
rm -rf out_tuple_write_negative
if "${HAXE_BIN:-haxe}" build.hxml \
	-D ocaml_structural_tuple_write_negative \
	-D ocaml_output=out_tuple_write_negative >"$tuple_write_log" 2>&1; then
	echo "reflaxe.ocaml accepted assignment to an immutable Map-pair field" >&2
	rm -f "$tuple_write_log"
	rm -rf out_tuple_write_negative
	exit 1
fi
if ! grep -Fq '[ocaml-structural-field:unsupported-tuple-write]' "$tuple_write_log"; then
	echo "Map-pair assignment failed without the typed tuple-write diagnostic" >&2
	cat "$tuple_write_log" >&2
	rm -f "$tuple_write_log"
	rm -rf out_tuple_write_negative
	exit 1
fi
rm -f "$tuple_write_log"
rm -rf out_tuple_write_negative

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
if (report.schemaVersion !== 47
	|| !report.summary?.valid
	|| report.lowering?.structuralFields?.length < 14
	|| report.summary.structuralFieldCount !== report.lowering.structuralFields.length) {
	throw new Error('reflaxe.ocaml inspection did not preserve the sealed structural-field decisions')
}
NODE

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const stored = report.structuralFields.find(field => field.operation === 'read-stored-field')
stored.operation = 'capture-iterator-method'
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
const tuple = report.structuralFields.find(field => field.operation === 'project-tuple-key')
tuple.keyValueTupleTarget.pairProducerCallId = 'call:corrupted'
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a Map-pair projection with corrupted typed producer evidence" >&2
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
const stored = report.structuralFields.find(field => field.runtimeUseOccurrences?.length > 0)
stored.runtimeUseOccurrences.pop()
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a stored field with a missing private runtime use" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const tuple = report.structuralFields.find(field => field.operation === 'project-tuple-key')
tuple.runtimeUseOccurrences = report.structuralFields.find(field => field.runtimeUseOccurrences?.length > 0).runtimeUseOccurrences
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a standard-library tuple projection with private runtime uses" >&2
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
