#!/usr/bin/env bash
set -euo pipefail

if [ "$(haxe --version)" != "4.3.7" ]; then
	echo "This behavior fixture requires upstream Haxe 4.3.7" >&2
	exit 1
fi

oracle_stdout="$(mktemp)"
rejected_stderr="$(mktemp)"
collision_root="$(mktemp -d)"
trap 'rm -f "$oracle_stdout" "$rejected_stderr"; rm -rf "$collision_root"' EXIT

haxe -cp src -main Main --interp >"$oracle_stdout"
collision_output="$collision_root/ocaml"
haxe build.hxml -D "ocaml_output=$collision_output" -D ocaml_build=native

test -f "$collision_output/Ocaml.ml"
test -f "$collision_output/reflaxe_ocaml_entry.ml"
test -x "$collision_output/_build/default/ocaml.exe"
"$collision_output/_build/default/ocaml.exe" | diff -u "$oracle_stdout" -

# Rebuild into the same public directory. Prior generated files must not change
# the current request's collision decision or create a new driver name.
haxe build.hxml -D "ocaml_output=$collision_output" -D ocaml_build=native
test -f "$collision_output/reflaxe_ocaml_entry.ml"
test ! -e "$collision_output/reflaxe_ocaml_entry_2.ml"
"$collision_output/_build/default/ocaml.exe" | diff -u "$oracle_stdout" -

case_output="$collision_root/HAXE"
haxe build.hxml -D "ocaml_output=$case_output" -D ocaml_build=byte
test -f "$case_output/Haxe.ml"
test -f "$case_output/reflaxe_ocaml_entry.ml"
test -f "$case_output/_build/default/haxe.bc"
dune exec --root "$case_output" ./haxe.bc | diff -u "$oracle_stdout" -

entry_count="$(grep -c 'entry-ran-once' "$oracle_stdout")"
if [ "$entry_count" -ne 1 ]; then
	echo "The executable entrypoint did not run exactly once" >&2
	exit 1
fi

if haxe build.hxml -D "ocaml_output=$collision_root/explicit" -D ocaml_build=native -D ocaml_dune_exes=ocaml 2>"$rejected_stderr"; then
	echo "An explicit executable replaced a case-equivalent generated module" >&2
	exit 1
fi
grep -Fq 'another current-program module owns the same case-equivalent filename' "$rejected_stderr"

echo "OUTPUT_EXECUTABLE_NAME_COLLISION:PASS"
