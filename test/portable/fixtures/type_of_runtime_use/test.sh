#!/usr/bin/env bash
set -euo pipefail

report="out/ocaml_runtime_requirement_report.json"
native="out/_build/default/out.exe"

node - "$report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const requirements = report.requirements.filter(entry =>
	entry.semanticCapability === 'haxe-typeof-runtime-classification'
		&& (entry.source.file === 'src/Main.hx' || entry.source.file === '(unknown)')
)

if (requirements.length !== 12) {
	throw new Error(`Expected twelve fixture-owned Type.typeof decisions, received ${requirements.length}`)
}
if (requirements.some(entry =>
	entry.implementationFeature !== 'haxe-typeof-runtime-classification-v1'
		|| entry.rootModules.join(',') !== 'HxEnum,HxRuntime,HxType'
		|| !entry.subject.id.startsWith('Type.typeof(')
)) {
	throw new Error(`Type.typeof requirements have incomplete source authority: ${JSON.stringify(requirements)}`)
}
NODE

for helper in \
	'HxRuntime.is_null' \
	'HxRuntime.is_boxed_bool' \
	'HxEnum.name_opt' \
	'HxType.enum_' \
	'HxType.getClass' \
	'HxType.class_'
do
	if ! grep -Fq "$helper" out/Main.ml; then
		echo "Generated Main.ml is missing planned helper $helper" >&2
		exit 1
	fi
done

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
	echo "Type.typeof runtime evidence changed across identical builds" >&2
	exit 1
fi

printf '%s\n' 'TYPE_OF_RUNTIME_USE_DETERMINISM:PASS'
