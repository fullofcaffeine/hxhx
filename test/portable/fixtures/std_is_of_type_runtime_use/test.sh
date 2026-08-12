#!/usr/bin/env bash
set -euo pipefail

node verify.js

sha256_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

first_main="$(sha256_file out/Main.ml)"
first_requirements="$(sha256_file out/ocaml_runtime_requirement_report.json)"

haxe build.hxml -D ocaml_build=native >/dev/null
node verify.js

second_main="$(sha256_file out/Main.ml)"
second_requirements="$(sha256_file out/ocaml_runtime_requirement_report.json)"

test "$first_main" = "$second_main"
test "$first_requirements" = "$second_requirements"
printf '%s\n' 'STD_IS_OF_TYPE_RUNTIME_USE_DETERMINISM:PASS'
