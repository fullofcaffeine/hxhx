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

if (fixtureDecisions.length !== 9
	|| nullable.length !== 1
	|| nullable[0].rootModules.join(',') !== 'HxRuntime,HxString'
	|| functionValues.length !== 1
	|| functionValues[0].rootModules.join(',') !== 'HxString') {
	throw new Error(`Unexpected String.fromCharCode runtime authority: ${JSON.stringify(fixtureDecisions)}`)
}
NODE

if [ "$(grep -Eo 'HxString\.fromCharCode' "$generated" | wc -l | tr -d ' ')" -ne 9 ]; then
	echo "Generated Main.ml does not contain the nine expected character-encoder uses" >&2
	exit 1
fi

first="$(shasum -a 256 "$report" | awk '{print $1}')"
haxe build.hxml >/dev/null
second="$(shasum -a 256 "$report" | awk '{print $1}')"
if [ "$first" != "$second" ]; then
	echo "String.fromCharCode runtime evidence changed across identical builds" >&2
	exit 1
fi
