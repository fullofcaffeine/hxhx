#!/usr/bin/env bash
set -euo pipefail

generated="out/Main.ml"
requirements="out/ocaml_runtime_requirement_report.json"
upstream_stdout="$(mktemp)"
native_stdout="$(mktemp)"
trap 'rm -f "$upstream_stdout" "$native_stdout"' EXIT

for symbol in \
	HxReflect.callMethod \
	HxReflect.isFunction \
	HxReflect.isObject \
	HxReflect.isEnumValue \
	HxReflect.same_closure \
	HxReflect.makeVarArgs \
	HxReflect.makeVarArgsVoid \
	HxAnon.get \
	HxAnon.set \
	HxAnon.has \
	HxAnon.fields \
	HxAnon.delete \
	HxAnon.copy; do
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
if (reflectRequirements.length !== 23) {
	throw new Error(`Expected twenty-three direct Reflect requirements, received ${reflectRequirements.length}`)
}
const expectedOwner = new Map([
	['field', 'HxAnon'],
	['getProperty', 'HxAnon'],
	['setField', 'HxAnon'],
	['hasField', 'HxAnon'],
	['fields', 'HxAnon'],
	['deleteField', 'HxAnon'],
	['copy', 'HxAnon']
])
for (const requirement of reflectRequirements) {
	const match = /^Reflect\.([^:]+):/.exec(requirement.subject.id)
	if (match === null) {
		throw new Error(`Direct Reflect requirement has an unreadable subject: ${JSON.stringify(requirement)}`)
	}
	const expectedRoot = expectedOwner.get(match[1]) ?? 'HxReflect'
	if (JSON.stringify(requirement.rootModules) !== JSON.stringify([expectedRoot])) {
		throw new Error(`Direct Reflect requirement has the wrong runtime owner: ${JSON.stringify(requirement)}`)
	}
}
NODE

# Stock Haxe 4.3.7 is the behavior oracle. The same authored Haxe program must
# produce the same observable values and argument order through generated OCaml.
haxe -cp src --main Main --interp >"$upstream_stdout"
out/_build/default/out.exe >"$native_stdout"
diff -u "$upstream_stdout" "$native_stdout"
