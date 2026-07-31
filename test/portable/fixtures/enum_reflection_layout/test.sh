#!/usr/bin/env bash
set -euo pipefail

REGISTRY="out/HxTypeRegistry.ml"
RUNTIME="out/runtime/HxType.ml"
EXECUTABLE="out/_build/default/out.exe"
FIRST_REGISTRY="$(mktemp)"
FIRST_RUNTIME="$(mktemp)"
ACTUAL_STDOUT="$(mktemp)"
trap 'rm -f "$FIRST_REGISTRY" "$FIRST_RUNTIME" "$ACTUAL_STDOUT"' EXIT

if [ ! -f "$REGISTRY" ] || [ ! -f "$RUNTIME" ] || [ ! -x "$EXECUTABLE" ]; then
	echo "Missing generated enum reflection registry, runtime, or executable" >&2
	exit 1
fi

"$EXECUTABLE" >"$ACTUAL_STDOUT"
diff -u expected.stdout "$ACTUAL_STDOUT"

node - "$REGISTRY" "$RUNTIME" <<'NODE'
const fs = require('fs')
const registry = fs.readFileSync(process.argv[2], 'utf8')
const runtime = fs.readFileSync(process.argv[3], 'utf8')

const expectedRows = [
	'HxType.register_enum_ctor_layout "MixedShape" "Alpha" 0 (HxType.EnumImmediate 0);',
	'HxType.register_enum_ctor_layout "MixedShape" "Bravo" 1 (HxType.EnumBlock 0);',
	'HxType.register_enum_ctor_layout "MixedShape" "Charlie" 2 (HxType.EnumImmediate 1);',
	'HxType.register_enum_ctor_layout "MixedShape" "Delta" 3 (HxType.EnumBlock 1);',
	'HxType.register_enum_ctor_layout "MixedShape" "Echo" 4 (HxType.EnumImmediate 2);',
]
for (const row of expectedRows) {
	if (!registry.includes(row))
		throw new Error(`Generated registry lost enum layout row: ${row}`)
}

if (!runtime.includes('enum_layout_for_value name value')
	|| !runtime.includes('Some layout -> layout.haxe_index')
	|| !runtime.includes('Some layout -> layout.name')) {
	throw new Error('Runtime reflection is not consuming the generated enum layout')
}
if (runtime.includes('List.nth ctors idx')) {
	throw new Error('Runtime reflection still treats an OCaml block tag as a Haxe constructor index')
}
NODE

cp "$REGISTRY" "$FIRST_REGISTRY"
cp "$RUNTIME" "$FIRST_RUNTIME"
haxe build.hxml
cmp "$FIRST_REGISTRY" "$REGISTRY"
cmp "$FIRST_RUNTIME" "$RUNTIME"
node verify-container-plan.js
