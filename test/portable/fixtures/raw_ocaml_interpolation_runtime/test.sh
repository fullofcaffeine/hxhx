#!/usr/bin/env bash
set -euo pipefail

# This fixture protects generated syntax, not only runtime output. Recompiling
# the same input must preserve the exact OCaml expression that surrounds the
# typed interpolation argument.
first_main="$(mktemp)"
trap 'rm -f "$first_main"' EXIT
cp out/Main.ml "$first_main"
haxe build.hxml -D ocaml_build=native
cmp "$first_main" out/Main.ml

echo "RAW_OCAML_INTERPOLATION_CLEAN_REPEAT:PASS"
