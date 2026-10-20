#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd ../../../.. && pwd)"
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
"${HAXE_BIN:-haxe}" -cp macros -cp "$ROOT/packages/reflaxe.ocaml/src" -lib reflaxe \
  --macro 'CheckGenericEnumCallback.install()' -main ContractCases --interp
echo "GENERIC_CLASS_ENUM_CALLBACK:PASS"
