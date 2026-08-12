#!/usr/bin/env bash
set -euo pipefail

report="out/ocaml_runtime_requirement_report.json"
generated="out/Main.ml"

node - "$report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const decisions = report.requirements.filter(entry =>
	entry.semanticCapability === 'haxe-string-field-read'
		&& (entry.source.file === 'src/Main.hx' || entry.source.file === '(unknown)')
)

if (decisions.length !== 4) {
	throw new Error(`Expected exactly four fixture-owned String.length decisions, received ${decisions.length}`)
}
if (decisions.some(entry => entry.rootModules.length !== 1 || entry.rootModules[0] !== 'HxString')) {
	throw new Error(`Unexpected String.length runtime roots: ${JSON.stringify(decisions)}`)
}
if (decisions.some(entry => entry.subject.id !== 'String.length -> Int')) {
	throw new Error(`Unexpected String.length type evidence: ${JSON.stringify(decisions)}`)
}
NODE

if ! grep -q 'let __string_receiver_' "$generated"; then
	echo "Generated String.length reads do not use an explicit receiver binding" >&2
	exit 1
fi

first="$(shasum -a 256 "$report" | awk '{print $1}')"
haxe build.hxml >/dev/null
second="$(shasum -a 256 "$report" | awk '{print $1}')"
if [ "$first" != "$second" ]; then
	echo "String.length runtime evidence changed across identical builds" >&2
	exit 1
fi
