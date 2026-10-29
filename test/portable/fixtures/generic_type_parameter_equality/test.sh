#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
echo "GENERIC_TYPE_PARAMETER_EQUALITY:PASS"
