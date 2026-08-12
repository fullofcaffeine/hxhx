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

if (requirements.length !== 13) {
	throw new Error(`Expected exactly thirteen fixture-owned static String decisions, received ${requirements.length}`)
}
if (requirements.some(entry => entry.rootModules.join(',') !== 'HxString')) {
	throw new Error(`Static String decisions must name only HxString: ${JSON.stringify(requirements)}`)
}
if (dynamicRequirements.length !== 3 || dynamicRequirements.some(entry => entry.rootModules.join(',') !== 'HxDynamic')) {
	throw new Error(`Dynamic conversion must keep its separate HxDynamic authority: ${JSON.stringify(dynamicRequirements)}`)
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
