#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-$ROOT/node_modules/.bin/haxe}"
mkdir -p "$ROOT/.tmp"
WORK_ROOT="$(mktemp -d "$ROOT/.tmp/shared-instance-method-body.XXXXXX")"
trap 'rm -rf "$WORK_ROOT"' EXIT

cd "$ROOT"
"$HAXE_BIN" test/reflaxe_ocaml_shared_instance_values/method-body.hxml
"$HAXE_BIN" -cp test/reflaxe_ocaml_shared_instance_values/source -main Main --interp
cd test/reflaxe_ocaml_shared_instance_values
"$HAXE_BIN" stock.hxml -D "ocaml_output=$WORK_ROOT/out"
cd "$WORK_ROOT/out"
dune build ./out.exe
./_build/default/out.exe
echo 'REFLAXE_OCAML_SHARED_INSTANCE_METHOD_BODY_STOCK_LIFECYCLE:PASS'
