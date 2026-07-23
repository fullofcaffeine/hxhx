#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/test/fixtures/native_parser_module_directives/NativeParserModuleDirectivesTest.ml"
mkdir -p "$ROOT/.tmp"
TMP_ROOT="$(mktemp -d "$ROOT/.tmp/native-parser-module-directives.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

if ! command -v ocamlc >/dev/null 2>&1; then
  echo "native parser module-directive smoke: missing ocamlc" >&2
  exit 127
fi

run_variant() {
  local variant="$1"
  local runtime_dir="$2"
  local build_dir="$TMP_ROOT/$variant"

  mkdir -p "$build_dir"
  ocamlc -c -o "$build_dir/HxHxNativeLexer.cmo" "$runtime_dir/HxHxNativeLexer.ml"
  ocamlc -c -I "$build_dir" -o "$build_dir/HxHxNativeParser.cmo" "$runtime_dir/HxHxNativeParser.ml"
  ocamlc -c -I "$build_dir" -o "$build_dir/NativeParserModuleDirectivesTest.cmo" "$RUNNER"
  ocamlc -I "$build_dir" \
    -o "$build_dir/native-parser-module-directives-test.exe" \
    "$build_dir/HxHxNativeLexer.cmo" \
    "$build_dir/HxHxNativeParser.cmo" \
    "$build_dir/NativeParserModuleDirectivesTest.cmo"
  "$build_dir/native-parser-module-directives-test.exe" "$variant"
}

run_variant source "$ROOT/packages/reflaxe.ocaml/std/runtime"
run_variant bootstrap "$ROOT/packages/hxhx/bootstrap_out/runtime"

echo "NATIVE_PARSER_MODULE_DIRECTIVES_SMOKE:PASS variants=2"
