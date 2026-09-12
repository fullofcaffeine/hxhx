#!/usr/bin/env bash
set -euo pipefail
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
if "${HAXE_BIN:-haxe}" -cp negative -main Main --no-output -lib reflaxe.ocaml -D no-traces -D no_traces -D "ocaml_output=$check_dir/out" > "$check_dir/compiler.log" 2>&1; then
  echo "recursive initializer unexpectedly compiled" >&2
  exit 1
fi
if ! rg -q 'ocaml-module-cycle:unsupported-initialization' "$check_dir/compiler.log"; then
  cat "$check_dir/compiler.log" >&2
  exit 1
fi
if [ -d "$check_dir/out" ] && [ -n "$(rg --files "$check_dir/out" -g '*.ml')" ]; then
  echo "rejected recursive initialization published OCaml modules" >&2
  exit 1
fi
echo "RECURSIVE_MODULE_INITIALIZER_REJECTION:PASS"
