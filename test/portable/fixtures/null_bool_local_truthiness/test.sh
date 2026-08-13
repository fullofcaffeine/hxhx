#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$source_file" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated source or lowering report" >&2
	exit 1
fi

if ! grep -Fq 'let plannedMutable = ref (HxRuntime.hx_null : Obj.t)' "$source_file"; then
	echo "The mutable Null<Bool> local did not use its selected Obj.t ref-cell carrier" >&2
	exit 1
fi
if ! grep -Fq 'let plannedCaptured = ref (Obj.repr true)' "$source_file"; then
	echo "The captured Null<Bool> local did not use its selected Obj.t ref-cell carrier" >&2
	exit 1
fi
if ! grep -Fq 'let directMutable = ref false' "$source_file"; then
	echo "The mutable exact Bool local did not use its selected bool ref-cell carrier" >&2
	exit 1
fi
if ! grep -Fq 'let directCaptured = ref true' "$source_file"; then
	echo "The captured exact Bool local did not use its selected bool ref-cell carrier" >&2
	exit 1
fi
if grep -Eq 'Obj\.magic \(!?(plannedCaptured|hx_plannedMutable)\)' "$source_file"; then
	echo "An admitted Null<Bool> ref-cell read still uses the legacy Obj.magic fallback" >&2
	exit 1
fi
if ! grep -Fq 'HxRuntime.unbox_bool_or_obj' "$source_file"; then
	echo "The generated conditions did not render their sealed nullable-Bool truthiness conversion" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('node:fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))

function fail(message) {
	console.error(`Null<Bool> lowering report check failed: ${message}`)
	process.exit(1)
}

if (report.schemaVersion !== 86
	|| report.representationScope !== 'exact-int-bool-int64-nullable-string-field-defaults-direct-simple-assignment-represented-array-locals-monomorphic-class-dynamic-internal-v15'
	|| report.localConversionModel !== 'typed-ocaml-local-carrier-conversions-v3'
	|| report.unsafeOperationModel !== 'proof-backed-admitted-unsafe-operations-v1'
	|| report.unsafeOperationCompleteness !== 'exact-null-int-null-bool-inline-dynamic-and-enum-to-dynamic-local-and-container-slices') {
	fail('unexpected schema, representation scope, or proof-ledger model')
}
const nullBoolDomains = new Set(report.representations
	.filter(entry => entry.semanticTypeId === 'Null<Bool>' && entry.carrierTypeId === 'Obj.t')
	.map(entry => entry.domain))
for (const domain of ['internal-value', 'mutable-local-storage', 'captured-local-storage']) {
	if (!nullBoolDomains.has(domain))
		fail(`missing exact Null<Bool> representation for ${domain}`)
}
const boolDomains = new Set(report.representations
	.filter(entry => entry.semanticTypeId === 'Bool' && entry.carrierTypeId === 'bool')
	.map(entry => entry.domain))
for (const domain of ['internal-value', 'mutable-local-storage', 'captured-local-storage']) {
	if (!boolDomains.has(domain))
		fail(`missing exact Bool representation for ${domain}`)
}
const conversions = report.localConversions.filter(entry => entry.source.file === 'src/Main.hx')
for (const conversion of ['preserve-nullable-bool-carrier', 'box-exact-bool-to-nullable-bool', 'nullable-bool-truthiness']) {
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
	&& entry.operation === 'obj-repr-exact-bool'
	&& entry.proofId === 'nullable-bool-box-exact-bool-v1')) {
	fail('missing proof-backed exact-Bool Obj.repr operation')
}
if (!report.unsafeOperations.some(entry => entry.source.file === 'src/Main.hx'
	&& entry.operation === 'nullable-bool-truthiness'
	&& entry.proofId === 'nullable-bool-truthiness-v1')) {
	fail('missing proof-backed nullable-Bool truthiness operation')
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
# Haxe 4.3.7's interpreter returns the typed Bool result for `null && rhs`.
# JavaScript and Neko preserve the null left operand instead. The OCaml target
# follows the interpreter's typed-Bool behavior while all three oracle routes
# must agree on condition truthiness and short-circuit side effects.
diff -u expected.js-neko.stdout out/oracle.js.stdout
diff -u expected.js-neko.stdout out/oracle.neko.stdout

echo "NULL_BOOL_LOCAL_TRUTHINESS_ORACLE_REPORT_AND_SOURCE_SHAPE:PASS"
