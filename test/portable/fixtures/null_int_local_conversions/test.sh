#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$source_file" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated source or lowering report" >&2
	exit 1
fi

if ! grep -Fq 'let hx_mutable = ref (HxRuntime.hx_null : Obj.t)' "$source_file"; then
	echo "The mutable Null<Int> local did not use its selected Obj.t ref-cell carrier" >&2
	exit 1
fi
if ! grep -Fq 'let captured = ref (Obj.repr 1)' "$source_file"; then
	echo "The captured Null<Int> local did not use its selected Obj.t ref-cell carrier" >&2
	exit 1
fi
if grep -Eq 'Obj\.magic \(!?(captured|hx_mutable)\)' "$source_file"; then
	echo "An admitted Null<Int> ref-cell read still uses the legacy Obj.magic fallback" >&2
	exit 1
fi
if ! grep -Fq 'HxRuntime.nullable_int_unwrap refined' "$source_file"; then
	echo "The flow-refined Null<Int> read did not use its sealed checked conversion" >&2
	exit 1
fi
if grep -Eq '__nullable_int_[0-9]+ = refined.*then 0 else Obj\.obj' "$source_file"; then
	echo "The flow-refined Null<Int> read still maps null to zero through the legacy fallback" >&2
	exit 1
fi
if ! grep -Fq 'HxRuntime.nullable_int_unwrap compoundValue' "$source_file"; then
	echo "The compound-assignment operand did not use its sealed checked Null<Int> conversion" >&2
	exit 1
fi
if grep -Eq 'Obj\.magic .*compoundValue' "$source_file"; then
	echo "The compound-assignment operand still uses an unproved Obj.magic fallback" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('node:fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const haxeSource = fs.readFileSync('src/Main.hx', 'utf8')

function fail(message) {
	console.error(`Null<Int> lowering report check failed: ${message}`)
	process.exit(1)
}

if (report.schemaVersion !== 67
	|| report.representationScope !== 'exact-int-bool-int64-nullable-string-field-defaults-direct-simple-assignment-represented-array-locals-monomorphic-class-dynamic-internal-v15'
	|| report.localConversionModel !== 'typed-ocaml-local-carrier-conversions-v3'
	|| report.unsafeOperationModel !== 'proof-backed-admitted-unsafe-operations-v1'
	|| report.unsafeOperationCompleteness !== 'exact-null-int-null-bool-inline-dynamic-and-enum-to-dynamic-local-and-container-slices') {
	fail('unexpected schema, representation scope, or proof-ledger model')
}
const nullIntDomains = new Set(report.representations
	.filter(entry => entry.semanticTypeId === 'Null<Int>' && entry.carrierTypeId === 'Obj.t')
	.map(entry => entry.domain))
for (const domain of ['internal-value', 'mutable-local-storage', 'captured-local-storage']) {
	if (!nullIntDomains.has(domain))
		fail(`missing exact Null<Int> representation for ${domain}`)
}
const conversions = report.localConversions.filter(entry => entry.source.file === 'src/Main.hx')
for (const conversion of ['preserve-nullable-int-carrier', 'box-exact-int-to-nullable-int', 'checked-unbox-nullable-int']) {
	if (!conversions.some(entry => entry.conversion === conversion))
		fail(`missing source conversion ${conversion}`)
}
const unsafeById = new Map(report.unsafeOperations.map(entry => [entry.id, entry]))
for (const conversion of report.localConversions) {
	const unsafeId = conversion.unsafeOperation?.id
	if (unsafeId == null)
		continue
	const unsafe = unsafeById.get(unsafeId)
	if (unsafe == null || unsafe.conversionId !== conversion.id
		|| unsafe.proofId !== conversion.proofId
		|| unsafe.programRevision !== conversion.programRevision
		|| unsafe.bodyRevision !== conversion.bodyRevision
		|| unsafe.pipelineRevision !== conversion.pipelineRevision) {
		fail(`unsafe proof does not match conversion ${conversion.id}`)
	}
}
if (!report.unsafeOperations.some(entry => entry.source.file === 'src/Main.hx'
	&& entry.operation === 'obj-repr-exact-int'
	&& entry.proofId === 'nullable-int-box-exact-int-v1')) {
	fail('missing proof-backed Obj.repr operation')
}
if (!report.unsafeOperations.some(entry => entry.source.file === 'src/Main.hx'
	&& entry.operation === 'checked-nullable-int-unwrap'
	&& entry.proofId === 'nullable-int-checked-read-v1')) {
	fail('missing proof-backed checked nullable read')
}
const compoundStatement = 'compoundTotal += compoundValue'
const compoundStatementOffset = haxeSource.indexOf(compoundStatement)
if (compoundStatementOffset < 0) {
	fail('missing compound-assignment source marker')
}
const compoundOffset = compoundStatementOffset + compoundStatement.indexOf('compoundValue')
const compoundConversions = conversions.filter(entry => entry.source.min === compoundOffset
	&& entry.inputSemanticTypeId === 'Null<Int>'
	&& entry.outputSemanticTypeId === 'Int'
	&& entry.conversion === 'checked-unbox-nullable-int')
if (compoundConversions.length !== 1) {
	fail(`expected one checked nullable-Int conversion for the compound operand, found ${compoundConversions.length}`)
}
NODE

if [ "$(haxe --version)" != "4.3.7" ]; then
	echo "This oracle fixture requires upstream Haxe 4.3.7" >&2
	exit 1
fi
haxe -cp src -main Main --interp >out/oracle.interp
haxe -cp src -main Main -js out/oracle.js
node out/oracle.js >out/oracle.js.stdout
haxe -cp src -main Main -neko out/oracle.n
neko out/oracle.n >out/oracle.neko.stdout

diff -u expected.stdout out/oracle.interp
diff -u expected.stdout out/oracle.js.stdout
diff -u expected.stdout out/oracle.neko.stdout

echo "NULL_INT_LOCAL_CONVERSIONS_ORACLE_REPORT_AND_SOURCE_SHAPE:PASS"
