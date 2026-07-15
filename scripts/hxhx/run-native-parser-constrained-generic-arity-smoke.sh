#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$ROOT/test/oracle/cpp_constrained_generic_arity_seed/src/Main.hx"
RUNNER="$ROOT/test/fixtures/native_parser_constrained_generic_arity/NativeParserConstrainedGenericArityTest.ml"
mkdir -p "$ROOT/.tmp"
TMP_ROOT="$(mktemp -d "$ROOT/.tmp/native-parser-constrained-generic-arity.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

if ! command -v ocamlc >/dev/null 2>&1; then
  echo "native parser constrained generic arity smoke: missing ocamlc" >&2
  exit 127
fi

run_variant() {
  local variant="$1"
  local runtime_dir="$2"
  local build_dir="$TMP_ROOT/$variant"

  mkdir -p "$build_dir"
  ocamlc -c -o "$build_dir/HxHxNativeLexer.cmo" "$runtime_dir/HxHxNativeLexer.ml"
  ocamlc -c -I "$build_dir" -o "$build_dir/HxHxNativeParser.cmo" "$runtime_dir/HxHxNativeParser.ml"
  ocamlc -c -I "$build_dir" -o "$build_dir/NativeParserConstrainedGenericArityTest.cmo" "$RUNNER"
  ocamlc -I "$build_dir" \
    -o "$build_dir/native-parser-constrained-generic-arity-test.exe" \
    "$build_dir/HxHxNativeLexer.cmo" \
    "$build_dir/HxHxNativeParser.cmo" \
    "$build_dir/NativeParserConstrainedGenericArityTest.cmo"
  "$build_dir/native-parser-constrained-generic-arity-test.exe" "$FIXTURE" "$variant"
}

run_variant source "$ROOT/packages/reflaxe.ocaml/std/runtime"
run_variant bootstrap "$ROOT/packages/hxhx/bootstrap_out/runtime"

echo "NATIVE_PARSER_CONSTRAINED_GENERIC_ARITY_SMOKE:PASS variants=2"
