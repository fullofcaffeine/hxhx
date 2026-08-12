#!/usr/bin/env bash
set -euo pipefail

DEFAULT_OUT="out"
NO_INLINE_OUT="out_no_inline"

generate() {
	local output="$1"
	shift
	haxe -cp src -main Main --no-output -lib reflaxe.ocaml \
		-D no-traces -D no_traces -D "ocaml_output=$output" \
		-D "ocaml_dune_exes=$output:Main" "$@"
}

build_and_run() {
	local output="$1"
	local executable_name="${output//-/_}"
	local executable="$output/_build/default/$executable_name.exe"
	if [ ! -x "$executable" ]; then
		echo "$executable was not built" >&2
		exit 1
	fi
	"$executable"
}

generate "$DEFAULT_OUT"
build_and_run "$DEFAULT_OUT" >actual-default.stdout
diff -u expected.stdout actual-default.stdout

generate "$NO_INLINE_OUT" -D no-inline
build_and_run "$NO_INLINE_OUT" >actual-no-inline.stdout
diff -u expected.stdout actual-no-inline.stdout
diff -u actual-default.stdout actual-no-inline.stdout

for generated in "$DEFAULT_OUT/Main.ml" "$NO_INLINE_OUT/Main.ml"; do
	if grep -Eq 'HxString\.url(Encode|Decode)' "$generated"; then
		echo "$generated contains a direct target-runtime URL-codec shortcut" >&2
		exit 1
	fi
done

if ! grep -q 'StringTools._urlEncodeOcaml' "$DEFAULT_OUT/Main.ml"; then
	echo "The default build does not call the Haxe-authored URL encoder" >&2
	exit 1
fi
if ! grep -q 'StringTools.urlEncode' "$NO_INLINE_OUT/Main.ml"; then
	echo "The no-inline build does not call the generated Haxe StringTools method" >&2
	exit 1
fi

printf '%s\n' "STRING_URL_CODEC_HAXE_OWNER:PASS"
