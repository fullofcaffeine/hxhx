#!/usr/bin/env bash
set -euo pipefail

report="out/ocaml_runtime_requirement_report.json"
native="out/_build/default/out.exe"

node - "$report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const requirements = report.requirements.filter(entry =>
	entry.semanticCapability === 'haxe-static-string-conversion'
		&& (entry.source.file === 'src/Main.hx' || entry.source.file === '(unknown)')
)
const dynamicRequirements = report.requirements.filter(entry =>
	entry.semanticCapability === 'haxe-dynamic-string'
		&& (entry.source.file === 'src/Main.hx' || entry.source.file === '(unknown)')
)

if (requirements.length !== 15) {
	throw new Error(`Expected exactly fifteen fixture-owned static String decisions, received ${requirements.length}`)
}
if (requirements.some(entry => entry.rootModules.join(',') !== 'HxString')) {
	throw new Error(`Static String decisions must name only HxString: ${JSON.stringify(requirements)}`)
}
if (dynamicRequirements.length !== 3 || dynamicRequirements.some(entry => entry.rootModules.join(',') !== 'HxDynamic')) {
	throw new Error(`Dynamic conversion must keep its separate HxDynamic authority: ${JSON.stringify(dynamicRequirements)}`)
}
NODE

# A concatenation of local String values has no work whose order can be
# observed. Keep that common case as direct OCaml instead of adding temporary
# variables that are only necessary for calls and other effectful expressions.
node - out/Main.ml <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const line = source.split('\n').find(line => line.startsWith('let pureConcat ='))
if (line == null) {
	throw new Error('Generated OCaml is missing pureConcat')
}
if (line.includes('__string_part_')) {
	throw new Error(`Pure String concatenation has unnecessary sequencing: ${line}`)
}
if (!line.includes(' ^ ')) {
	throw new Error(`Pure String concatenation is not direct OCaml: ${line}`)
}
NODE

# Upstream Haxe 4.3.7 is the independent behavior oracle. Compare its output
# with the real native OCaml executable so a shared generated expectation
# cannot hide a target-side null or evaluation-order error.
oracle_output="$(mktemp)"
native_output="$(mktemp)"
trap 'rm -f "$oracle_output" "$native_output"' EXIT
haxe -cp src --main Main --interp >"$oracle_output"
"$native" >"$native_output"
diff -u "$oracle_output" "$native_output"

first="$(shasum -a 256 "$report" | awk '{print $1}')"
haxe build.hxml >/dev/null
second="$(shasum -a 256 "$report" | awk '{print $1}')"
if [ "$first" != "$second" ]; then
	echo "Static String runtime evidence changed across identical builds" >&2
	exit 1
fi
