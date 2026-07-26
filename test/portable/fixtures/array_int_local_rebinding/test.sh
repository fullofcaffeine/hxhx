#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
if [ ! -f "$source_file" ]; then
	echo "Missing generated source: $source_file" >&2
	exit 1
fi

if grep -Eq 'ref \(Obj\.magic \(let __arr_' "$source_file"; then
	echo "An admitted Array<Int> ref cell still casts its initializer with Obj.magic" >&2
	exit 1
fi

if grep -Eq 'let __assign_[0-9]+ = Obj\.magic \(let __arr_' "$source_file"; then
	echo "An admitted Array<Int> replacement still casts the new carrier with Obj.magic" >&2
	exit 1
fi

if grep -Eq 'HxArray\.(get|set) \(Obj\.magic \(!?values\)\)' "$source_file"; then
	echo "An admitted Array<Int> local read still casts its HxArray receiver with Obj.magic" >&2
	exit 1
fi

haxe -cp src -main Main --interp >out/oracle.interp
haxe -cp src -main Main -js out/oracle.js
node out/oracle.js >out/oracle.js.stdout
haxe -cp src -main Main -neko out/oracle.n
neko out/oracle.n >out/oracle.neko.stdout

diff -u expected.stdout out/oracle.interp
diff -u expected.stdout out/oracle.js.stdout
diff -u expected.stdout out/oracle.neko.stdout

echo "ARRAY_INT_LOCAL_REBINDING_ORACLE_AND_SOURCE_SHAPE:PASS"
