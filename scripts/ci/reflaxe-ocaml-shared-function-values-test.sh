#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-$ROOT/node_modules/.bin/haxe}"
mkdir -p "$ROOT/.tmp"
WORK_ROOT="$(mktemp -d "$ROOT/.tmp/shared-function-values-stock.XXXXXX")"
trap 'rm -rf "$WORK_ROOT"' EXIT

cd "$ROOT"
"$HAXE_BIN" test/reflaxe_ocaml_shared_function_values/test.hxml
cd test/reflaxe_ocaml_shared_function_values
"$HAXE_BIN" stock.hxml -D "ocaml_output=$WORK_ROOT/out"
cp Observer.ml "$WORK_ROOT/out/Observer.ml"
cd "$WORK_ROOT/out"
dune build ./out.exe
./_build/default/out.exe
ocamlopt -thread -I +threads -I +unix -I +str -I +dynlink \
  -I _build/default/runtime/.hx_runtime.objs/byte \
  -I _build/default/runtime/.hx_runtime.objs/native \
  unix.cmxa str.cmxa threads.cmxa dynlink.cmxa \
  _build/default/runtime/hx_runtime.cmxa Main.ml Observer.ml -o observer.exe
./observer.exe
echo 'REFLAXE_OCAML_SHARED_FUNCTION_VALUES_STOCK_LIFECYCLE:PASS'
