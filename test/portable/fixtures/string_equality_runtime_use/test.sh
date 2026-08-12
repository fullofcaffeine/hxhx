#!/usr/bin/env bash
set -euo pipefail

report="out/ocaml_runtime_requirement_report.json"
generated="out/Main.ml"

node - "$report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const decisions = report.requirements.filter(entry =>
	entry.semanticCapability === 'haxe-string-equality'
)
const fixtureDecisions = decisions.filter(entry =>
	entry.source.file === 'src/Main.hx' || entry.source.file === '(unknown)'
)
const equal = fixtureDecisions.filter(entry => entry.subject.id.includes(' equal '))
const notEqual = fixtureDecisions.filter(entry => entry.subject.id.includes(' not-equal '))

if (fixtureDecisions.length !== 8
	|| equal.length !== 4
	|| notEqual.length !== 4
	|| fixtureDecisions.some(entry => entry.rootModules.join(',') !== 'HxString')) {
	throw new Error(`Unexpected String equality runtime authority: ${JSON.stringify(fixtureDecisions)}`)
}
NODE

if [ "$(grep -Eo 'HxString\.equals' "$generated" | wc -l | tr -d ' ')" -ne 8 ]; then
	echo "Generated Main.ml does not contain the eight expected String equality uses" >&2
	exit 1
fi

first="$(shasum -a 256 "$report" | awk '{print $1}')"
haxe build.hxml >/dev/null
second="$(shasum -a 256 "$report" | awk '{print $1}')"
if [ "$first" != "$second" ]; then
	echo "String equality runtime evidence changed across identical builds" >&2
	exit 1
fi
