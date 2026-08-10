#!/usr/bin/env bash
set -euo pipefail

builder="../../../../packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx"
generated="out/Main.ml"

if grep -q 'HxBootArray\|missingTrailingRestArgValue\|isOmittableTrailingRestArg' "$builder"; then
	echo "Standalone reflaxe.ocaml must not repair missing typed rest arguments with the Stage3 HxBootArray shim" >&2
	exit 1
fi

if grep -q 'HxBootArray' "$generated"; then
	echo "Valid typed rest calls must not emit the Stage3 HxBootArray shim" >&2
	exit 1
fi

if [ "$(grep -c 'HxArray.create' "$generated")" -lt 4 ]; then
	echo "Haxe must supply normal empty or populated HxArray values for every rest call in this fixture" >&2
	exit 1
fi

if ! grep -q 'HxArray.length' "$generated"; then
	echo "The extern rest call must reach its real HxArray.length target" >&2
	exit 1
fi

echo "REST_EMPTY_TYPED_ARRAY_BOUNDARY:PASS"
