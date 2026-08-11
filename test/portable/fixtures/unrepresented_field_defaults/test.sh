#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
oracle_output="$(mktemp)"
trap 'rm -f "$oracle_output"' EXIT

if [ ! -f "$source_file" ]; then
	echo "Missing generated source for unrepresented field defaults" >&2
	exit 1
fi

# Haxe eval is the independent behavior oracle for omitted reference fields.
haxe -cp src --run Main >"$oracle_output"
diff -u expected.stdout "$oracle_output"

if ! grep -Eq '^type childholder_t = .*mutable inheritedValue : Obj\.t.*mutable dynamicValue : Obj\.t.*mutable classValue : ReferenceValue\.t.*mutable enumValue : DefaultChoice\.defaultchoice' "$source_file"; then
	echo "The child record does not contain the expected inherited and local fields" >&2
	exit 1
fi

# The checked runtime identifier is atomic OCaml syntax. The printer can include
# or omit parentheses around it without changing the selected Haxe null value.
null='Obj\.magic (HxRuntime\.hx_null|\(HxRuntime\.hx_null\))'
if ! grep -Eq "childholder_create.*inheritedValue = $null.*dynamicValue = $null.*classValue = $null.*enumValue = $null" "$source_file"; then
	echo "Each uninitialized reference field must receive the checked Haxe null value" >&2
	exit 1
fi

echo "UNREPRESENTED_FIELD_DEFAULTS:PASS"
