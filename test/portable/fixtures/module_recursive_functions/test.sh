#!/usr/bin/env bash
set -euo pipefail
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
for source in negative unsafe; do
  case "$source" in
    negative) code=unsupported-initialization ;;
    unsafe) code=unsafe-literal-cycle ;;
  esac
  if "${HAXE_BIN:-haxe}" -cp "$source" -main Main --no-output -lib reflaxe.ocaml -D no-traces -D no_traces -D "ocaml_output=$check_dir/$source" > "$check_dir/$source.log" 2>&1; then
    echo "recursive initialization unexpectedly compiled: $source" >&2
    exit 1
  fi
  if ! grep -Fq "ocaml-module-cycle:$code" "$check_dir/$source.log"; then
    cat "$check_dir/$source.log" >&2
    exit 1
  fi
  if [ -d "$check_dir/$source" ] && [ -n "$(find "$check_dir/$source" -type f -name '*.ml' -print)" ]; then
    echo "rejected recursive initialization published OCaml modules: $source" >&2
    exit 1
  fi
done
echo "RECURSIVE_MODULE_INITIALIZER_REJECTION:PASS"
