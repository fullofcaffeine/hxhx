#!/usr/bin/env bash
set -euo pipefail

# The same Haxe program must preserve anonymous-object behavior through vanilla
# JS, vanilla Neko, and native OCaml. The report checks below additionally prove
# that native code came from validated object operations rather than a printer
# guessing from field names while it emitted OCaml text.
ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
RUNTIME_REPORT_FILE="out/ocaml_runtime_requirement_report.json"
FIRST_REPORT="$(mktemp)"
INSPECTION_REPORT="$(mktemp)"
INVALID_LOG="$(mktemp)"
ORACLE_DIR="$(mktemp -d)"
OVERFLOW_OUTPUT="out-overflow-$$"
OVERFLOW_EXECUTABLE="${OVERFLOW_OUTPUT//-/_}.exe"
INVALID_SCHEDULE_OUTPUT="out-invalid-anonymous-schedule-$$"
INVALID_REVISION_OUTPUT="out-invalid-anonymous-revision-$$"
INVALID_ORDER_OUTPUT="out-invalid-anonymous-order-$$"
INVALID_RUNTIME_USE_OUTPUT="out-invalid-anonymous-runtime-use-$$"
trap 'rm -f "$FIRST_REPORT" "$INSPECTION_REPORT" "$INVALID_LOG"; rm -rf "$ORACLE_DIR" "$OVERFLOW_OUTPUT" "$INVALID_SCHEDULE_OUTPUT" "$INVALID_REVISION_OUTPUT" "$INVALID_ORDER_OUTPUT" "$INVALID_RUNTIME_USE_OUTPUT"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ] || [ ! -f "$RUNTIME_REPORT_FILE" ]; then
	echo "Missing generated anonymous-object source, lowering report, or runtime report" >&2
	exit 1
fi

haxe -cp src -main Main -js "$ORACLE_DIR/main.js"
node "$ORACLE_DIR/main.js" >"$ORACLE_DIR/js.stdout"
diff -u expected.stdout "$ORACLE_DIR/js.stdout"

haxe -cp src -main Main -neko "$ORACLE_DIR/main.n"
neko "$ORACLE_DIR/main.n" >"$ORACLE_DIR/neko.stdout"
diff -u expected.stdout "$ORACLE_DIR/neko.stdout"

# JavaScript represents Haxe `Int` values with JavaScript numbers, so this
# particular overflow edge does not wrap on the stock JS target. Neko and the
# Haxe evaluator provide the signed 32-bit oracle used by native OCaml.
haxe -cp src -main Main -D anon_overflow_probe -js "$ORACLE_DIR/overflow.js"
node "$ORACLE_DIR/overflow.js" >"$ORACLE_DIR/overflow-js.stdout"
diff -u expected.overflow-js.stdout "$ORACLE_DIR/overflow-js.stdout"

haxe -cp src -main Main -D anon_overflow_probe -neko "$ORACLE_DIR/overflow.n"
neko "$ORACLE_DIR/overflow.n" >"$ORACLE_DIR/overflow-neko.stdout"
diff -u expected.overflow-int32.stdout "$ORACLE_DIR/overflow-neko.stdout"

haxe -cp src -D anon_overflow_probe --run Main >"$ORACLE_DIR/overflow-eval.stdout"
diff -u expected.overflow-int32.stdout "$ORACLE_DIR/overflow-eval.stdout"

haxe build.hxml -D anon_overflow_probe -D "ocaml_output=$OVERFLOW_OUTPUT"
"$OVERFLOW_OUTPUT/_build/default/$OVERFLOW_EXECUTABLE" >"$ORACLE_DIR/overflow-ocaml.stdout"
diff -u expected.overflow-int32.stdout "$ORACLE_DIR/overflow-ocaml.stdout"

node - "$SOURCE_FILE" "$REPORT_FILE" "$RUNTIME_REPORT_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const runtimeReport = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'))
const sha256 = /^sha256:[0-9a-f]{64}$/

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 85
	|| report.anonymousStructureModel !== 'ocaml-anonymous-structure-v4'
	|| report.anonymousStructures?.length !== report.anonymousStructureCount
	|| report.anonymousStructureOperations?.length !== report.anonymousStructureOperationCount
	|| !sha256.test(report.anonymousStructureRevision)) {
	fail('unexpected anonymous-object report schema, model, inventory, or revision')
}

const structure = report.anonymousStructures.find(item => item.semanticTypeId === 'anonymous{a:Int,b:String,flag:Bool}')
if (!structure) {
	fail('the report has no BasicAnon runtime shape')
}
if (report.anonymousStructures.some(item => item.semanticTypeId.includes('inc:'))) {
	fail('the bounded plan incorrectly claimed the method-bearing anonymous object')
}
const fields = structure.fields ?? []
if (structure.carrierTypeId !== 'Obj.t'
	|| structure.representationDomain !== 'internal-value'
	|| structure.identityPolicy !== 'reference-identity'
	|| structure.aliasingPolicy !== 'shared-reference-aliases'
	|| structure.mutationPolicy !== 'mutable-runtime-container'
	|| fields.map(field => field.name).join(',') !== 'a,b,flag'
	|| fields.map(field => `${field.semanticTypeId}/${field.carrierTypeId}`).join(',') !== 'Int/int,String/string,Bool/bool'
	|| fields[2].storeConversion !== 'box-bool'
	|| fields[2].loadConversion !== 'unbox-bool') {
	fail('the anonymous-object shape does not preserve exact fields, carriers, identity, aliases, and mutation')
}

const operations = report.anonymousStructureOperations.filter(operation =>
	operation.structureId === structure.id
	&& operation.source?.file === 'src/Main.hx')
const countByKind = new Map()
const expectedSchedules = new Map([
	['create', 'create-container,result-container'],
	['initialize-field', 'field-value,box-field-value,store-field'],
	['read-field', 'receiver,lookup-field,unbox-field-value,result-value'],
	['write-field', 'receiver,field-value,box-field-value,store-field,result-value'],
	['compound-write-field', 'receiver,lookup-field,unbox-old-field-value,field-value,apply-field-operator,box-field-value,store-field,result-value']
])
for (const operation of operations) {
	countByKind.set(operation.kind, (countByKind.get(operation.kind) ?? 0) + 1)
	const compoundWrite = operation.kind === 'compound-write-field'
	const boolCarrier = operation.loadConversion === 'unbox-bool' || operation.storeConversion === 'box-bool'
	const expectedRequirementIds = [
		`${operation.id}:runtime:haxe-anonymous-structure`,
		...(boolCarrier ? [`${operation.id}:runtime:haxe-anonymous-bool-carrier`] : []),
		...(compoundWrite ? [`${operation.id}:runtime:haxe-int32-add`] : [])
	]
	if (operation.structureId !== structure.id
		|| operation.structureRevision !== structure.revision
		|| operation.pipelineRevision !== 'ocaml-function-plans-v108'
		|| operation.proofId !== 'direct-anonymous-runtime-operations-v3'
		|| operation.evaluationSchedule.join(',') !== expectedSchedules.get(operation.kind)
		|| operation.runtimeModule !== 'HxAnon'
		|| operation.runtimeRequirementIds?.join(',') !== expectedRequirementIds.join(',')
		|| operation.runtimeReadOperation !== (compoundWrite ? 'get' : null)
		|| operation.fieldOperator !== (compoundWrite ? 'int-add' : null)) {
		fail(`anonymous operation ${operation.id} does not preserve its sealed shape, schedule, proof, or runtime owner`)
	}
	const requirementId = operation.runtimeRequirementIds[0]
	const requirement = report.runtimeRequirements.find(item => item.id === requirementId)
	if (!requirement
		|| requirement.decisionId !== operation.id
		|| requirement.sourceId !== operation.occurrenceId
		|| requirement.semanticCapability !== 'haxe-anonymous-structure'
		|| requirement.implementationFeature !== 'haxe-anonymous-structure-v1'
		|| requirement.rootModules?.join(',') !== 'HxAnon') {
		fail(`anonymous operation ${operation.id} has no exact HxAnon runtime explanation`)
	}
	if (boolCarrier) {
		const boolRequirement = report.runtimeRequirements.find(item => item.id === expectedRequirementIds[1])
		if (!boolRequirement
			|| boolRequirement.decisionId !== operation.id
			|| boolRequirement.sourceId !== operation.occurrenceId
			|| boolRequirement.semanticCapability !== 'haxe-anonymous-bool-carrier'
			|| boolRequirement.implementationFeature !== 'haxe-boolean-carrier-v1'
			|| boolRequirement.rootModules?.join(',') !== 'HxRuntime') {
			fail(`anonymous operation ${operation.id} has no exact HxRuntime Boolean-carrier explanation`)
		}
	}
	if (compoundWrite) {
		const arithmetic = report.runtimeRequirements.find(item => item.id === `${operation.id}:runtime:haxe-int32-add`)
		if (!arithmetic
			|| arithmetic.decisionId !== operation.id
			|| arithmetic.sourceId !== operation.occurrenceId
			|| arithmetic.semanticCapability !== 'haxe-int32-add'
			|| arithmetic.implementationFeature !== 'haxe-int32-arithmetic-v1'
			|| arithmetic.rootModules?.join(',') !== 'HxInt') {
			fail(`anonymous compound write ${operation.id} has no exact HxInt arithmetic explanation`)
		}
	}
	const expectedUses = operation.kind === 'create'
		? [['HxAnon.create', 'create-container']]
		: operation.kind === 'initialize-field'
			? [['HxAnon.set', 'initialize-field'], ...(boolCarrier ? [['HxRuntime.box_bool', 'box-field-value']] : [])]
			: operation.kind === 'read-field'
				? [...(boolCarrier ? [['HxRuntime.unbox_bool_or_obj', 'unbox-field-value']] : []), ['HxAnon.get', 'read-field']]
				: operation.kind === 'write-field'
					? [['HxAnon.set', 'write-field'], ...(boolCarrier ? [['HxRuntime.box_bool', 'box-field-value']] : [])]
					: [['HxAnon.get', 'read-field'], ['HxInt.add', 'apply-field-operator'], ['HxAnon.set', 'write-field']]
	if (operation.runtimeUseOccurrences?.length !== expectedUses.length)
		fail(`anonymous operation ${operation.id} has no exact private-runtime use inventory`)
	for (const [index, [symbol, role]] of expectedUses.entries()) {
		const use = operation.runtimeUseOccurrences[index]
		if (use.ownerId !== operation.id
			|| use.exactSymbol !== symbol
			|| use.role !== role
			|| use.order !== index
			|| use.cardinality !== 1
			|| use.domain !== 'expression-identifier'
			|| !sha256.test(use.planRevision)) {
			fail(`anonymous operation ${operation.id} has a stale private-runtime use at index ${index}`)
		}
	}
}
if (countByKind.get('create') !== 1
	|| countByKind.get('initialize-field') !== 3
	|| countByKind.get('read-field') !== 4
	|| countByKind.get('write-field') !== 1
	|| countByKind.get('compound-write-field') !== 1) {
	fail(`unexpected anonymous operation partition: ${JSON.stringify(Object.fromEntries(countByKind))}`)
}

if (runtimeReport.authorityStatus !== 'partial'
	|| runtimeReport.compilerObservationGranularity !== 'module-name-only'
	|| !runtimeReport.compilerObservedModulesWithRequirementRoots.includes('HxAnon')
	|| !runtimeReport.compilerObservedModulesWithRequirementRoots.includes('HxEnum')
	|| runtimeReport.compilerObservedModulesWithoutRequirementRoots.includes('HxAnon')
	|| runtimeReport.compilerObservedModulesWithoutRequirementRoots.includes('HxEnum')
	|| !runtimeReport.message.includes('does not prove that every generated use')) {
	fail('runtime reporting lost HxAnon/HxEnum requirement roots or overstated occurrence ownership')
}

if (!/let __anonymous_value_[0-9]+ = HxAnon\.create \(\)/.test(source)
	|| !/let __anonymous_field_value_[0-9]+ = let __call_arg_0_[0-9]+ = "field-flag" in let __call_arg_1_[0-9]+ = false in markedBool __call_arg_0_[0-9]+ __call_arg_1_[0-9]+ in ignore \(HxAnon\.set __anonymous_value_[0-9]+ "flag" \(HxRuntime\.box_bool __anonymous_field_value_[0-9]+\)\)/.test(source)
	|| !/let __anonymous_receiver_[0-9]+ = o in let __anonymous_old_field_value_[0-9]+ = Obj\.obj \(HxAnon\.get __anonymous_receiver_[0-9]+ "a"\) in let __anonymous_field_value_[0-9]+ =/.test(source)
	|| !/let __anonymous_new_field_value_[0-9]+ = HxInt\.add __anonymous_old_field_value_[0-9]+ __anonymous_field_value_[0-9]+/.test(source)
	|| !/HxAnon\.set __anonymous_receiver_[0-9]+ "a" \(Obj\.repr __anonymous_new_field_value_[0-9]+\)/.test(source)
	|| !/let __anonymous_receiver_[0-9]+ = o in let __anonymous_field_value_[0-9]+ = true/.test(source)
	|| !/HxRuntime\.box_bool __anonymous_field_value_[0-9]+/.test(source)
	|| !/let __anonymous_field_value_[0-9]+ = let __string_receiver_[0-9]+ = data in let __string_argument_0_[0-9]+ = 0 in let __string_argument_1_[0-9]+ = Obj\.obj \(HxAnon\.get span "pos"\) in HxString\.substr __string_receiver_[0-9]+ __string_argument_0_[0-9]+ __string_argument_1_[0-9]+ in ignore \(HxAnon\.set __anonymous_value_[0-9]+ "p" \(Obj\.repr __anonymous_field_value_[0-9]+\)\)/.test(source)) {
	fail('generated OCaml did not mechanically consume the planned allocation, isolated literal field value, Bool carrier, or single-evaluation Int += schedule')
}
NODE

cp "$REPORT_FILE" "$FIRST_REPORT"
haxe build.hxml
if ! cmp -s "$FIRST_REPORT" "$REPORT_FILE"; then
	echo "The same typed program produced a different anonymous-object report" >&2
	diff -u "$FIRST_REPORT" "$REPORT_FILE" >&2 || true
	exit 1
fi

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$INSPECTION_REPORT"

node - "$INSPECTION_REPORT" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (report.schemaVersion !== 47
	|| !report.summary?.valid
	|| report.summary.anonymousStructureCount !== report.lowering?.anonymousStructures?.length
	|| report.summary.anonymousStructureOperationCount !== report.lowering?.anonymousStructureOperations?.length
	|| !report.lowering.anonymousStructures.some(item => item.semanticTypeId === 'anonymous{a:Int,b:String,flag:Bool}')
	|| report.lowering.anonymousStructureOperations.filter(item =>
		item.sourceFile === 'src/Main.hx'
		&& item.structureId === report.lowering.anonymousStructures.find(
			structure => structure.semanticTypeId === 'anonymous{a:Int,b:String,flag:Bool}')?.id).length !== 10
	|| !report.lowering.anonymousStructureOperations.some(item =>
		item.kind === 'compound-write-field'
		&& item.fieldOperator === 'int-add'
		&& item.runtimeReadOperation === 'get'
		&& item.runtimeRequirementIds?.length === 2
		&& item.runtimeUseOccurrences?.map(use => use.exactSymbol).join(',') === 'HxAnon.get,HxInt.add,HxAnon.set')) {
	throw new Error('public inspection did not preserve the validated anonymous-object inventory')
}
NODE

cp -R out "$INVALID_SCHEDULE_OUTPUT"
node - "$INVALID_SCHEDULE_OUTPUT/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const read = report.anonymousStructureOperations.find(operation => operation.kind === 'read-field')
if (!read) {
	throw new Error('fixture has no anonymous read to corrupt')
}
read.evaluationSchedule = ['lookup-field', 'receiver', 'unbox-field-value', 'result-value']
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output "$INVALID_SCHEDULE_OUTPUT" --require-lowering --json >"$INVALID_LOG" 2>&1; then
	echo "Public inspection accepted an anonymous read with a corrupt evaluation schedule" >&2
	exit 1
fi
if ! grep -Fq "invalid-read" "$INVALID_LOG"; then
	echo "Public inspection rejected the corrupt anonymous read without an actionable reason" >&2
	cat "$INVALID_LOG" >&2
	exit 1
fi

cp -R out "$INVALID_REVISION_OUTPUT"
node - "$INVALID_REVISION_OUTPUT/ocaml_lowering_report.json" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const structure = report.anonymousStructures.find(item => item.semanticTypeId === 'anonymous{a:Int,b:String,flag:Bool}')
const representation = report.representations.find(item => item.id === structure?.representationId)
if (!representation) {
	throw new Error('fixture has no anonymous-object representation to corrupt')
}
representation.revision = `sha256:${'0'.repeat(64)}`
report.representationRevision = 'sha256:' + crypto.createHash('sha256')
	.update(JSON.stringify(report.representations)).digest('hex')
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output "$INVALID_REVISION_OUTPUT" --require-lowering --json >"$INVALID_LOG" 2>&1; then
	echo "Public inspection accepted an anonymous structure whose representation revision was stale" >&2
	exit 1
fi
if ! grep -Fq "revision does not match its reported leaf facts" "$INVALID_LOG"; then
	echo "Public inspection rejected the stale anonymous representation for an unrelated reason" >&2
	cat "$INVALID_LOG" >&2
	exit 1
fi

cp -R out "$INVALID_ORDER_OUTPUT"
node - "$INVALID_ORDER_OUTPUT/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
report.anonymousStructureOperations.reverse()
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output "$INVALID_ORDER_OUTPUT" --require-lowering --json >"$INVALID_LOG" 2>&1; then
	echo "Public inspection accepted reordered anonymous-operation evidence" >&2
	exit 1
fi
if ! grep -Fq "anonymous operation inventory is not in strict identity order" "$INVALID_LOG"; then
	echo "Public inspection rejected reordered anonymous-operation evidence without an actionable reason" >&2
	cat "$INVALID_LOG" >&2
	exit 1
fi

cp -R out "$INVALID_RUNTIME_USE_OUTPUT"
node - "$INVALID_RUNTIME_USE_OUTPUT/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const operation = report.anonymousStructureOperations.find(item => item.runtimeUseOccurrences?.length > 1)
if (!operation) {
	throw new Error('fixture has no multi-use anonymous operation to corrupt')
}
operation.runtimeUseOccurrences.reverse()
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output "$INVALID_RUNTIME_USE_OUTPUT" --require-lowering --json >"$INVALID_LOG" 2>&1; then
	echo "Public inspection accepted an anonymous operation with reordered private-runtime permissions" >&2
	exit 1
fi
if ! grep -Fq "wrong-runtime-use" "$INVALID_LOG"; then
	echo "Public inspection rejected reordered private-runtime permissions without an actionable reason" >&2
	cat "$INVALID_LOG" >&2
	exit 1
fi

echo "ANONYMOUS_STRUCTURE_REPORT_AND_ORACLE:PASS"
