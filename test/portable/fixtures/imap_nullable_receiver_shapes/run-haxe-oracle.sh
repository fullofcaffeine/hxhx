#!/usr/bin/env bash
set -euo pipefail

# Compares expected.stdout with the Haxe 4.3.7 eval target (`haxe --interp`).
# The OCaml fixture uses the same expected output, so a passing run here and in
# the portable runner shows that reflaxe.ocaml matches upstream Haxe for every
# nullable Map receiver shape in src/Main.hx, including the null failures.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-ocaml-nullable-map-receivers.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

haxe_version="$(haxe --version)"
if [ "$haxe_version" != "4.3.7" ]; then
	echo "Expected the Haxe 4.3.7 behavior oracle, found $haxe_version." >&2
	exit 1
fi

haxe -cp "$script_dir/src" -main Main --interp >"$tmp_dir/interp.stdout"
diff -u "$script_dir/expected.stdout" "$tmp_dir/interp.stdout"

echo "HAXE_4_3_7_NULLABLE_MAP_RECEIVER_ORACLE:PASS"
