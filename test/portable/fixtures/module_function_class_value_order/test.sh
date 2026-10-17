#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
echo 'MODULE_FUNCTION_CLASS_VALUE_ORDER:PASS'
