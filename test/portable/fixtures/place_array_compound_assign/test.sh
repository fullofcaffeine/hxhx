#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$source_file" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated array source or lowering report" >&2
	exit 1
fi

if grep -Fq 'let base = Obj.magic (receiver ())' "$source_file"; then
	echo "The compiler-generated Array<Int> receiver local fell back to the generic same-class Obj.magic cast" >&2
	exit 1
fi

if ! grep -Fq 'let base = receiver ()' "$source_file"; then
	echo "Expected the sealed Array<Int> identity conversion to copy receiver() directly into base" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const intMutations = report.plans.filter(item =>
	item.nodeKind === 'array-compound-assignment'
	|| item.nodeKind === 'array-int-update')
if (intMutations.length === 0
	|| intMutations.some(item => item.runtimeUseOccurrences?.length !== 1
		|| item.runtimeUseOccurrences[0].exactSymbol !== 'HxInt.add'
		|| item.runtimeUseOccurrences[0].requirementId !== item.runtimeRequirementIds.find(id => id.endsWith(':runtime:haxe-int32-add')))) {
	throw new Error('each sealed array Int mutation must own its exact HxInt.add runtime occurrence')
}
NODE

echo "ARRAY_INT_RECEIVER_CARRIER_SOURCE_SHAPE:PASS"
