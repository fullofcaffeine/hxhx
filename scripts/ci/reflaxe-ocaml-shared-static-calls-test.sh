#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-$ROOT/node_modules/.bin/haxe}"
mkdir -p "$ROOT/.tmp"
WORK_ROOT="$(mktemp -d "$ROOT/.tmp/shared-static-calls-stock.XXXXXX")"
trap 'rm -rf "$WORK_ROOT"' EXIT

cd "$ROOT"
"$HAXE_BIN" test/reflaxe_ocaml_shared_static_calls/test.hxml
cd test/reflaxe_ocaml_shared_static_calls
"$HAXE_BIN" stock.hxml -D "ocaml_output=$WORK_ROOT/out"
cd "$WORK_ROOT/out"
dune build ./out.exe
./_build/default/out.exe > "$WORK_ROOT/stdout" 2> "$WORK_ROOT/stderr"
test ! -s "$WORK_ROOT/stdout"
test ! -s "$WORK_ROOT/stderr"
echo 'REFLAXE_OCAML_SHARED_STATIC_CALLS_STOCK_LIFECYCLE:PASS'
