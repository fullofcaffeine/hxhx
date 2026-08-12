#!/usr/bin/env bash
set -euo pipefail

report="out/ocaml_runtime_requirement_report.json"
generated="out/Main.ml"

node - "$report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const decisions = report.requirements.filter(entry =>
	entry.semanticCapability === 'haxe-string-method'
		&& (entry.source.file === 'src/Main.hx' || entry.source.file === '(unknown)')
)

if (decisions.length !== 26) {
	throw new Error(`Expected exactly 26 fixture-owned String method decisions, received ${decisions.length}`)
}
if (decisions.some(entry => entry.rootModules.some(root => root !== 'HxString' && root !== 'HxRuntime'))) {
	throw new Error(`Unexpected String method runtime roots: ${JSON.stringify(decisions)}`)
}
for (const method of ['toUpperCase', 'toLowerCase', 'charAt', 'charCodeAt', 'indexOf', 'lastIndexOf', 'split', 'substr', 'substring', 'toString']) {
	if (!decisions.some(entry => entry.subject.id.includes(`.${method}(`))) {
		throw new Error(`Missing planned String method evidence for ${method}`)
	}
}
NODE

if grep -Eq 'HxString\.(lastIndexOf|substring) \([^\n]*\) \([^\n]*\) \(HxString\.length \(' "$generated"; then
	echo "Generated String defaults do not visibly use a receiver binding" >&2
	exit 1
fi

first="$(shasum -a 256 "$report" | awk '{print $1}')"
haxe build.hxml >/dev/null
second="$(shasum -a 256 "$report" | awk '{print $1}')"
if [ "$first" != "$second" ]; then
	echo "String method runtime evidence changed across identical builds" >&2
	exit 1
fi
