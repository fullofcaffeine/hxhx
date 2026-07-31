#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
if [ ! -f "$source_file" ]; then
	echo "Missing generated source: $source_file" >&2
	exit 1
fi

if grep -Fq 'let base = Obj.magic (receiver ())' "$source_file"; then
	echo "The compiler-generated Array<Int> receiver local fell back to the generic same-class Obj.magic cast" >&2
	exit 1
fi

if ! grep -Fq 'let base = receiver ()' "$source_file"; then
	echo "Expected the sealed Array<Int> identity conversion to copy receiver() directly into base" >&2
	exit 1
fi

echo "ARRAY_INT_RECEIVER_CARRIER_SOURCE_SHAPE:PASS"
