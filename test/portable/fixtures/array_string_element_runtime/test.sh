#!/usr/bin/env bash
set -euo pipefail

report_file="out/ocaml_lowering_report.json"
if [ ! -f "$report_file" ]; then
	echo "Missing generated lowering report: $report_file" >&2
	exit 1
fi

# This child proves only that exact String can be an array element. A later
# task must deliberately construct an Array<String> descriptor and producer,
# so this real program must still report neither of those product decisions.
node - "$report_file" <<'NODE'
const fs = require('node:fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))

if (report.representedArrays.some(entry => entry.arraySemanticTypeId === 'Array<String>')) {
	throw new Error('String ArrayElement proof unexpectedly admitted an Array<String> descriptor')
}
if (report.arrayLiteralProducers.some(entry => entry.arraySemanticTypeId === 'Array<String>')) {
	throw new Error('String ArrayElement proof unexpectedly admitted an Array<String> literal producer')
}
NODE

bash ../../../../scripts/reflaxe-ocaml/run-string-array-element-oracle.sh

echo "STRING_ARRAY_ELEMENT_RUNTIME_BOUNDARY:PASS"
