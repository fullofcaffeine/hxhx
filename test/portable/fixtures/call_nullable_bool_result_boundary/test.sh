#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
if [ ! -f "$source_file" ]; then
	echo "Missing generated nullable Boolean result fixture" >&2
	exit 1
fi

function_source="$(sed -n '/^let hasValues =/,/^let main =/p' "$source_file")"
if ! printf '%s\n' "$function_source" | grep -Fq 'try Obj.repr ((' \
	|| ! printf '%s\n' "$function_source" | grep -Eq 'HxRuntime[.]Hx_return __ret_[0-9]+ -> [(]__ret_[0-9]+ : Obj[.]t[)]'; then
	echo "The result-only boundary must box normal Bool completion and recover every return as Obj.t" >&2
	exit 1
fi
if printf '%s\n' "$function_source" | grep -Fq 'Obj.obj'; then
	echo "The nullable Boolean result boundary must not infer its recovered value through Obj.obj" >&2
	exit 1
fi
