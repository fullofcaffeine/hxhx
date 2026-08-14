#!/usr/bin/env bash
set -euo pipefail

report="out/ocaml_runtime_requirement_report.json"
generated="out/Main.ml"

node - "$report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const decisions = report.requirements.filter(entry =>
	entry.semanticCapability === 'haxe-string-from-char-code'
)
const fixtureDecisions = decisions.filter(entry =>
	entry.source.file === 'src/Main.hx' || entry.source.file === '(unknown)'
)
const nullable = fixtureDecisions.filter(entry =>
	entry.subject.id === 'Null<Int> -> String'
)
const functionValues = fixtureDecisions.filter(entry =>
	entry.subject.id === 'String.fromCharCode function value'
)
const nullableBySource = new Map()
for (const entry of nullable) {
	const key = `${entry.source.file}:${entry.source.min}:${entry.source.max}`
	const entries = nullableBySource.get(key) ?? []
	entries.push(entry)
	nullableBySource.set(key, entries)
}
const copiedNullableSites = [...nullableBySource.values()].filter(entries => entries.length === 2)

if (fixtureDecisions.length !== 11
	|| nullable.length !== 3
	|| nullable.some(entry => entry.rootModules.join(',') !== 'HxRuntime,HxString')
	|| copiedNullableSites.length !== 1
	|| copiedNullableSites[0][0].id === copiedNullableSites[0][1].id
	|| functionValues.length !== 1
	|| functionValues[0].rootModules.join(',') !== 'HxString') {
	throw new Error(`Unexpected String.fromCharCode runtime authority: ${JSON.stringify(fixtureDecisions)}`)
}
NODE

if [ "$(grep -Eo 'HxString\.fromCharCode' "$generated" | wc -l | tr -d ' ')" -ne 12 ]; then
	echo "Generated Main.ml does not contain the twelve expected character-encoder output sites" >&2
	exit 1
fi

first="$(shasum -a 256 "$report" | awk '{print $1}')"
haxe build.hxml >/dev/null
second="$(shasum -a 256 "$report" | awk '{print $1}')"
if [ "$first" != "$second" ]; then
	echo "String.fromCharCode runtime evidence changed across identical builds" >&2
	exit 1
fi
