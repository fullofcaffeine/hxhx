#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-$ROOT/node_modules/.bin/haxe}"
mkdir -p "$ROOT/.tmp"
WORK_ROOT="$(mktemp -d "$ROOT/.tmp/shared-nullable-values-stock.XXXXXX")"
trap 'rm -rf "$WORK_ROOT"' EXIT

cd "$ROOT/test/reflaxe_ocaml_shared_nullable_values"
"$HAXE_BIN" stock.hxml -D "ocaml_output=$WORK_ROOT/out" \
  -D "reflaxe_ocaml_shared_program_output=$WORK_ROOT/shared"
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
cd "$WORK_ROOT/shared"
dune build ./reflaxe_ocaml_entry.exe
./_build/default/reflaxe_ocaml_entry.exe
cp "$ROOT/test/reflaxe_ocaml_shared_nullable_values/Observer.ml" Observer.ml
ocamlopt -I runtime runtime/HxRuntime.ml Main.ml Observer.ml -o observer.exe
./observer.exe
echo 'REFLAXE_OCAML_SHARED_NULLABLE_VALUES_STOCK_LIFECYCLE:PASS'
