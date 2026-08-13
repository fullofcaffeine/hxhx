#!/usr/bin/env bash
set -euo pipefail

failure_log="$(mktemp)"
trap 'rm -f "$failure_log"' EXIT
rm -rf cycle-out

if haxe cycle.hxml >"$failure_log" 2>&1; then
	echo "The same-module class-carrier cycle unexpectedly compiled." >&2
	exit 1
fi

grep -Fq "[ocaml-type-order:unsupported-cycle]" "$failure_log"
if [ -e cycle-out/CycleMain.ml ]; then
	echo "The rejected class-carrier cycle published generated OCaml." >&2
	exit 1
fi
