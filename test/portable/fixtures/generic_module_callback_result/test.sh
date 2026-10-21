#!/usr/bin/env bash
set -euo pipefail
"${HAXE_BIN:-haxe}" contracts.hxml
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
echo "GENERIC_MODULE_CALLBACK_RESULT:PASS"
