#!/usr/bin/env bash
set -euo pipefail

generated="out/Main.ml"
requirements="out/ocaml_runtime_requirement_report.json"

for symbol in \
	HxReflect.callMethod \
	HxReflect.isFunction \
	HxReflect.isObject \
	HxReflect.isEnumValue \
	HxReflect.same_closure \
	HxReflect.makeVarArgs \
	HxReflect.makeVarArgsVoid; do
	if ! grep -Fq "$symbol" "$generated"; then
		echo "Generated OCaml does not use the planned Reflect helper: $symbol" >&2
		exit 1
	fi
done

# The source-level Reflect calls must not remain unresolved in generated OCaml.
if grep -Eq '(^|[^A-Za-z0-9_])Reflect\.' "$generated"; then
	echo "A standard Reflect call escaped the target plan" >&2
	exit 1
fi

node - "$requirements" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const reflectRequirements = report.requirements.filter(
	requirement => requirement.semanticCapability === 'haxe-reflect-runtime-call'
)
if (reflectRequirements.length !== 14) {
	throw new Error(`Expected fourteen direct Reflect requirements, received ${reflectRequirements.length}`)
}
for (const requirement of reflectRequirements) {
	if (JSON.stringify(requirement.rootModules) !== JSON.stringify(['HxReflect'])) {
		throw new Error(`Direct Reflect requirement has the wrong runtime owner: ${JSON.stringify(requirement)}`)
	}
}
NODE
