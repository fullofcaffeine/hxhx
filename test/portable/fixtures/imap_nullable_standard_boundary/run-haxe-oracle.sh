#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-ocaml-nullable-map-oracle.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

haxe_version="$(haxe --version)"
if [ "$haxe_version" != "4.3.7" ]; then
	echo "Expected the Haxe 4.3.7 behavior oracle, found $haxe_version." >&2
	exit 1
fi

# Stock targets agree on valid Map values. They differ after an invalid null
# access: eval, Neko, and Python throw, while JavaScript returns null. The OCaml
# fixture uses the fail-closed result in expected.stdout, and this script keeps
# the JavaScript difference visible instead of presenting it as universal Haxe
# behavior.
haxe -cp "$script_dir/src" -main Main --interp >"$tmp_dir/interp.stdout"
diff -u "$script_dir/expected.stdout" "$tmp_dir/interp.stdout"

haxe -cp "$script_dir/src" -main Main -js "$tmp_dir/main.js"
node "$tmp_dir/main.js" >"$tmp_dir/js.stdout"
diff -u "$script_dir/expected.js.stdout" "$tmp_dir/js.stdout"

if command -v neko >/dev/null 2>&1; then
	haxe -cp "$script_dir/src" -main Main -neko "$tmp_dir/main.n"
	neko "$tmp_dir/main.n" >"$tmp_dir/neko.stdout"
	diff -u "$script_dir/expected.stdout" "$tmp_dir/neko.stdout"
fi

if command -v python3 >/dev/null 2>&1; then
	haxe -cp "$script_dir/src" -main Main -python "$tmp_dir/main.py"
	python3 "$tmp_dir/main.py" >"$tmp_dir/python.stdout"
	diff -u "$script_dir/expected.stdout" "$tmp_dir/python.stdout"
fi

echo "HAXE_4_3_7_NULLABLE_STANDARD_MAP_ORACLE:PASS"
