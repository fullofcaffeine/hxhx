#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-$ROOT/node_modules/.bin/haxe}"
mkdir -p "$ROOT/.tmp"
WORK_ROOT="$(mktemp -d "$ROOT/.tmp/runtime-authority-host.XXXXXX")"
trap 'rm -rf "$WORK_ROOT"' EXIT
cd "$ROOT"
"$HAXE_BIN" -cp packages/reflaxe.ocaml/src \
  -cp test/reflaxe_ocaml_runtime_authority_host/src \
  -main RuntimeAuthorityHostFixture -neko "$WORK_ROOT/authority.n"
neko "$WORK_ROOT/authority.n" "$ROOT/packages/reflaxe.ocaml/std/runtime"
